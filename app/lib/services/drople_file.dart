import 'dart:convert';

import 'package:file_picker/file_picker.dart';
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
  /// Menggunakan file picker native untuk memilih direktori.
  Future<String?> setReceiveDirectory(String peerId) async {
    // file_picker 13.x: result.files returns List<PlatformFile>
    final result = await FilePicker.platform.pickFiles(
      type: FileType.any,
      dialogTitle: 'Pilih folder untuk menerima file dari $peerId',
    );

    // Handle null result safely
    if (result == null) {
      return null;
    }

    // result.files adalah List<PlatformFile>
    final selectedDir = result.files.first.path;
    
    if (selectedDir == null) {
      return null;
    }

    // Simpan path ke database Rust via FFI
    return _bindings.fileReceive(peerId, selectedDir);
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
