import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';

class MyFileGua {
  MyFileGua._();

  static Future<Directory> _directory() async {
    final docs = await getApplicationDocumentsDirectory();
    final directory = Directory(
      '${docs.path}${Platform.pathSeparator}Drople${Platform.pathSeparator}MyFileGua',
    );
    await directory.create(recursive: true);
    return directory;
  }

  static Future<File> _messagesFile() async {
    final directory = await _directory();
    return File('${directory.path}${Platform.pathSeparator}.messages.json');
  }

  static Future<List<File>> listFiles() async {
    final directory = await _directory();
    final files = directory
        .listSync()
        .whereType<File>()
        .where((file) => !file.uri.pathSegments.last.startsWith('.'))
        .toList();
    files.sort((a, b) => b.lastModifiedSync().compareTo(a.lastModifiedSync()));
    return files;
  }

  static Future<List<File>> addFiles(List<PlatformFile> picked) async {
    final directory = await _directory();
    final added = <File>[];
    for (final item in picked) {
      final source = item.path;
      if (source == null) continue;
      var target = File(
        '${directory.path}${Platform.pathSeparator}${item.name}',
      );
      if (await target.exists()) {
        final dot = item.name.lastIndexOf('.');
        final stem = dot > 0 ? item.name.substring(0, dot) : item.name;
        final extension = dot > 0 ? item.name.substring(dot) : '';
        target = File(
          '${directory.path}${Platform.pathSeparator}${stem}_${DateTime.now().microsecondsSinceEpoch}$extension',
        );
      }
      added.add(await File(source).copy(target.path));
    }
    return added;
  }

  static Future<void> deleteFile(File file) async {
    if (await file.exists()) await file.delete();
  }

  static Future<List<MyFileGuaMessage>> listMessages() async {
    final file = await _messagesFile();
    if (!await file.exists()) return [];
    try {
      final values = jsonDecode(await file.readAsString()) as List<dynamic>;
      return values
          .map(
            (value) => MyFileGuaMessage.fromJson(value as Map<String, dynamic>),
          )
          .toList();
    } catch (_) {
      return [];
    }
  }

  static Future<void> addMessage(String text) async {
    await _appendMessage(
      MyFileGuaMessage(
        id: DateTime.now().microsecondsSinceEpoch.toString(),
        text: text.trim(),
        createdAt: DateTime.now().millisecondsSinceEpoch,
      ),
    );
  }

  static Future<void> addAttachmentMessage(String fileName) async {
    await _appendMessage(
      MyFileGuaMessage(
        id: DateTime.now().microsecondsSinceEpoch.toString(),
        text: '',
        createdAt: DateTime.now().millisecondsSinceEpoch,
        attachmentName: fileName,
      ),
    );
  }

  static Future<void> _appendMessage(MyFileGuaMessage message) async {
    final messages = await listMessages();
    messages.add(message);
    final file = await _messagesFile();
    await file.writeAsString(
      jsonEncode(messages.map((message) => message.toJson()).toList()),
      flush: true,
    );
  }
}

class MyFileGuaMessage {
  const MyFileGuaMessage({
    required this.id,
    required this.text,
    required this.createdAt,
    this.attachmentName,
  });

  final String id;
  final String text;
  final int createdAt;
  final String? attachmentName;

  factory MyFileGuaMessage.fromJson(Map<String, dynamic> json) =>
      MyFileGuaMessage(
        id: json['id'] as String,
        text: json['text'] as String,
        createdAt: (json['created_at'] as num).toInt(),
        attachmentName: json['attachment_name'] as String?,
      );

  Map<String, dynamic> toJson() => {
    'id': id,
    'text': text,
    'created_at': createdAt,
    if (attachmentName != null) 'attachment_name': attachmentName,
  };
}
