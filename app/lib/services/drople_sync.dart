import 'dart:convert';

import '../ffi/drople_bindings.dart';

/// Wrapper tingkat tinggi untuk fungsi sinkronisasi CRDT via FFI.
class DropleSync {
  DropleSync({DropleBindings? bindings}) : _injected = bindings;

  final DropleBindings? _injected;
  late final DropleBindings _bindings = _injected ?? DropleBindings.instance;

  /// Dapatkan status sinkronisasi sebuah catatan.
  String syncStatus(String noteId) {
    return _bindings.noteSyncStatus(noteId);
  }

  /// Dapatkan daftar catatan yang perlu sinkronisasi (JSON).
  List<Map<String, dynamic>> pendingList() {
    final data = jsonDecode(_bindings.notePendingListJson()) as List<dynamic>;
    return data.cast<Map<String, dynamic>>();
  }

  /// Terapkan delta catatan dari peer ke database lokal.
  void applyDelta(String deltaJson, String localPeerId) {
    _bindings.noteApplyDelta(deltaJson, localPeerId);
  }

  /// Tandai semua catatan pending sebagai synced.
  void markAllSynced() {
    _bindings.noteMarkAllSynced();
  }

  /// Memicu proses sinkronisasi dua arah via P2P dengan peer tertentu.
  void syncWithPeer(String peerId) {
    _bindings.noteSyncWithPeer(peerId);
  }
}
