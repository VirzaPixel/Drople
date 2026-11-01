import 'dart:convert';

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
  /// Gunakan input teks path (fallback jika file_picker unable build Android).
  String setReceiveDirectory(String peerId, String savePath) {
    return _bindings.fileReceive(peerId, savePath);
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
