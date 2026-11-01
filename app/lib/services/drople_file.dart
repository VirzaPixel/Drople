import 'dart:convert';
import 'dart:io';

import 'package:open_filex/open_filex.dart';

import '../ffi/drople_bindings.dart';
import '../models/file_transfer.dart';

/// Wrapper tingkat tinggi untuk transfer file P2P via Core Rust.
class DropleFile {
  DropleFile({DropleBindings? bindings}) : _injected = bindings;

  final DropleBindings? _injected;
  late final DropleBindings _bindings = _injected ?? DropleBindings.instance;

  /// Mengirim file lokal ke peer yang dituju.
  /// Mengembalikan id transfer.
  String sendFile(String peerId, String filePath) {
    return _bindings.fileSend(peerId, filePath);
  }

  /// Menyiapkan folder tujuan penerimaan file.
  String setReceiveDirectory(String peerId, String savePath) {
    return _bindings.fileReceive(peerId, savePath);
  }

  /// Menentukan folder default penerimaan file.
  void setDefaultReceiveDirectory(String savePath) {
    _bindings.fileSetReceiveDir(savePath);
  }

  /// Membuka file hasil transfer dengan aplikasi bawaan perangkat.
  Future<String> openTransfer(FileTransferItem item) async {
    final path = item.localPath;
    if (path == null || path.trim().isEmpty) {
      return 'Lokasi file tidak diketahui';
    }
    if (!File(path).existsSync()) {
      return 'File sudah tidak ada di perangkat';
    }
    final result = await OpenFilex.open(path);
    if (result.type == ResultType.done) return '';
    return result.message.isEmpty ? 'Tidak ada aplikasi pembuka' : result.message;
  }

  /// Mengambil daftar semua transfer file (riwayat + aktif).
  List<FileTransferItem> listTransfers() {
    final raw = _bindings.fileListJson();
    final data = jsonDecode(raw) as List<dynamic>;
    return data
        .map((e) => FileTransferItem.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// Mengambil status transfer tertentu ('pending'|'active'|'completed'|'failed').
  String transferStatus(String transferId) {
    return _bindings.fileTransferStatus(transferId);
  }
}
