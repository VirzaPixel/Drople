import 'dart:convert';

import '../ffi/drople_bindings.dart';
import '../models/backup_item.dart';

/// Wrapper tingkat tinggi untuk backup terenkripsi E2EE ke Google Drive via Rust Core.
class DropleBackup {
  DropleBackup({DropleBindings? bindings}) : _injected = bindings;

  final DropleBindings? _injected;
  late final DropleBindings _bindings = _injected ?? DropleBindings.instance;

  /// Mengambil atau membuat recovery key 12 kata untuk akun ini.
  String getOrCreateRecoveryKey() => _bindings.backupRecoveryKey();

  /// Mengeset recovery key dari 12 kata mnemonic (misal saat restore di device baru).
  void setRecoveryKey(String mnemonic) {
    _bindings.backupSetRecoveryKey(mnemonic);
  }

  /// Cek apakah recovery key sudah tersimpan di database lokal.
  bool isRecoveryKeyConfigured() => _bindings.backupIsConfigured();

  /// Simpan OAuth token Google Drive ke database.
  void setGoogleDriveToken({
    required String accessToken,
    required String refreshToken,
    required int expiresAt,
  }) {
    _bindings.gdriveSetToken(accessToken, refreshToken, expiresAt);
  }

  /// Set client id dan secret kustom (opsional).
  void setGoogleClient({
    required String clientId,
    required String clientSecret,
  }) {
    _bindings.gdriveSetClient(clientId, clientSecret);
  }

  /// Apakah Google Drive saat ini terhubung dan memiliki token yang valid.
  bool isConnected() => _bindings.gdriveIsConnected();

  /// Melakukan backup snapshot sekarang, terenkripsi XChaCha20-Poly1305.
  /// Mengembalikan id file di Google Drive.
  String backupNow() => _bindings.gdriveBackup();

  /// Daftar file snapshot backup yang ada di Google Drive `appDataFolder`.
  List<BackupItem> listBackups() {
    final raw = _bindings.gdriveBackupListJson();
    final data = jsonDecode(raw) as List<dynamic>;
    return data
        .map((e) => BackupItem.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// Restore database dari snapshot backup di Drive, menggunakan CRDT merge.
  void restore(String backupId) {
    _bindings.gdriveRestore(backupId);
  }

  /// Hapus snapshot backup dari Google Drive.
  void delete(String backupId) {
    _bindings.gdriveDelete(backupId);
  }

  /// Putuskan koneksi Google Drive (menghapus token).
  void disconnect() {
    _bindings.gdriveDisconnect();
  }
}
