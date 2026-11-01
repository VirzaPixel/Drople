import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import '../ffi/drople_bindings.dart';
import '../models/note.dart';

/// Wrapper tingkat tinggi untuk Core Rust.
class DropleCore {
  DropleCore({DropleBindings? bindings}) : _injected = bindings;

  final DropleBindings? _injected;
  late final DropleBindings _bindings = _injected ?? DropleBindings.instance;
  bool _initialized = false;

  Future<void> init() async {
    if (_initialized) return;
    final dir = await getApplicationSupportDirectory();
    final dbPath = '${dir.path}${Platform.pathSeparator}drople.db';
    final rc = _bindings.init(dbPath);
    if (rc != 0) {
      throw StateError('drople_init gagal (kode $rc)');
    }
    _initialized = true;
  }

  List<NoteSummary> listNotes() {
    final data = jsonDecode(_bindings.noteListJson()) as List<dynamic>;
    return data
        .map((e) => NoteSummary.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  String createNote(String title, String content) =>
      _bindings.noteCreate(title, content);

  ({String title, String content}) getNote(String id) => _bindings.noteGet(id);

  void updateNote(String id, String title, String content) =>
      _bindings.noteUpdate(id, title, content);

  void deleteNote(String id) => _bindings.noteDelete(id);

  void setFavorite(String id, bool favorite) =>
      _bindings.noteSetFavorite(id, favorite);
}
