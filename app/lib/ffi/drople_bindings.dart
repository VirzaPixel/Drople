import 'dart:ffi' as ffi;
import 'dart:io';

import 'package:ffi/ffi.dart';

typedef _InitNative = ffi.Int32 Function(ffi.Pointer<Utf8>);
typedef _InitDart = int Function(ffi.Pointer<Utf8>);

typedef _VoidNative = ffi.Void Function();
typedef _VoidDart = void Function();

typedef _FreeNative = ffi.Void Function(ffi.Pointer<Utf8>);
typedef _FreeDart = void Function(ffi.Pointer<Utf8>);

typedef _CreateNative = ffi.Int32 Function(
  ffi.Pointer<Utf8>,
  ffi.Pointer<Utf8>,
  ffi.Pointer<ffi.Pointer<Utf8>>,
);
typedef _CreateDart = int Function(
  ffi.Pointer<Utf8>,
  ffi.Pointer<Utf8>,
  ffi.Pointer<ffi.Pointer<Utf8>>,
);

typedef _GetNative = ffi.Int32 Function(
  ffi.Pointer<Utf8>,
  ffi.Pointer<ffi.Pointer<Utf8>>,
  ffi.Pointer<ffi.Pointer<Utf8>>,
);
typedef _GetDart = int Function(
  ffi.Pointer<Utf8>,
  ffi.Pointer<ffi.Pointer<Utf8>>,
  ffi.Pointer<ffi.Pointer<Utf8>>,
);

typedef _UpdateNative = ffi.Int32 Function(
  ffi.Pointer<Utf8>,
  ffi.Pointer<Utf8>,
  ffi.Pointer<Utf8>,
);
typedef _UpdateDart = int Function(
  ffi.Pointer<Utf8>,
  ffi.Pointer<Utf8>,
  ffi.Pointer<Utf8>,
);

typedef _DeleteNative = ffi.Int32 Function(ffi.Pointer<Utf8>);
typedef _DeleteDart = int Function(ffi.Pointer<Utf8>);

typedef _ListNative = ffi.Int32 Function(ffi.Pointer<ffi.Pointer<Utf8>>);
typedef _ListDart = int Function(ffi.Pointer<ffi.Pointer<Utf8>>);

typedef _NoArgNative = ffi.Int32 Function();
typedef _NoArgDart = int Function();

typedef _CodeNative = ffi.Int32 Function(ffi.Pointer<Utf8>);
typedef _CodeDart = int Function(ffi.Pointer<Utf8>);

typedef _SyncStatusNative = ffi.Int32 Function(
  ffi.Pointer<Utf8>,
  ffi.Pointer<ffi.Pointer<Utf8>>,
);
typedef _SyncStatusDart = int Function(
  ffi.Pointer<Utf8>,
  ffi.Pointer<ffi.Pointer<Utf8>>,
);

typedef _ApplyDeltaNative = ffi.Int32 Function(
  ffi.Pointer<Utf8>,
  ffi.Pointer<Utf8>,
);
typedef _ApplyDeltaDart = int Function(ffi.Pointer<Utf8>, ffi.Pointer<Utf8>);

typedef _FileSendNative = ffi.Int32 Function(
  ffi.Pointer<Utf8>,
  ffi.Pointer<Utf8>,
  ffi.Pointer<ffi.Pointer<Utf8>>,
);
typedef _FileSendDart = int Function(
  ffi.Pointer<Utf8>,
  ffi.Pointer<Utf8>,
  ffi.Pointer<ffi.Pointer<Utf8>>,
);

typedef _FileStatusNative = ffi.Int32 Function(
  ffi.Pointer<Utf8>,
  ffi.Pointer<ffi.Pointer<Utf8>>,
);
typedef _FileStatusDart = int Function(
  ffi.Pointer<Utf8>,
  ffi.Pointer<ffi.Pointer<Utf8>>,
);

typedef _SetTokenNative = ffi.Int32 Function(
  ffi.Pointer<Utf8>,
  ffi.Pointer<Utf8>,
  ffi.Int64,
);
typedef _SetTokenDart = int Function(
  ffi.Pointer<Utf8>,
  ffi.Pointer<Utf8>,
  int,
);

typedef _BoolOutNative = ffi.Int32 Function(ffi.Pointer<ffi.Int32>);
typedef _BoolOutDart = int Function(ffi.Pointer<ffi.Int32>);

typedef _TwoStringNative = ffi.Int32 Function(
  ffi.Pointer<Utf8>,
  ffi.Pointer<Utf8>,
);
typedef _TwoStringDart = int Function(
  ffi.Pointer<Utf8>,
  ffi.Pointer<Utf8>,
);

typedef _FavoriteNative = ffi.Int32 Function(ffi.Pointer<Utf8>, ffi.Int32);
typedef _FavoriteDart = int Function(ffi.Pointer<Utf8>, int);

/// Low-level FFI bindings ke `drople_core`.
class DropleBindings {
  DropleBindings._(this._lib);

  final ffi.DynamicLibrary _lib;

  static DropleBindings? _instance;

  static DropleBindings get instance => _instance ??= DropleBindings._(_load());

  static String get _libName {
    if (Platform.isWindows) return 'drople_core.dll';
    if (Platform.isMacOS) return 'libdrople_core.dylib';
    return 'libdrople_core.so';
  }

  static ffi.DynamicLibrary _load() {
    if (Platform.isAndroid) {
      return ffi.DynamicLibrary.open(_libName);
    }

    final candidates = <String>[];

    final override = Platform.environment['DROPLE_CORE_LIB'];
    if (override != null && override.trim().isNotEmpty) {
      candidates.add(override.trim());
    }

    final exeDir = File(Platform.resolvedExecutable).parent.path;
    candidates.add('$exeDir/lib/$_libName');
    candidates.add('native/$_libName');
    candidates.add('app/native/$_libName');
    candidates.add('core/target/release/$_libName');
    candidates.add('core/target/debug/$_libName');
    candidates.add(_libName);

    final errors = <String>[];
    for (final path in candidates) {
      try {
        return ffi.DynamicLibrary.open(path);
      } catch (e) {
        errors.add('  $path -> $e');
      }
    }
    throw StateError(
      'Tidak dapat memuat $_libName. Kandidat yang dicoba:\n${errors.join('\n')}',
    );
  }

  int init(String dbPath) {
    final p = dbPath.toNativeUtf8();
    try {
      return _lib.lookupFunction<_InitNative, _InitDart>('drople_init')(p);
    } finally {
      malloc.free(p);
    }
  }

  void cleanup() {
    _lib.lookupFunction<_VoidNative, _VoidDart>('drople_cleanup')();
  }

  void _free(ffi.Pointer<Utf8> ptr) {
    if (ptr == ffi.nullptr) return;
    _lib.lookupFunction<_FreeNative, _FreeDart>('drople_string_free')(ptr);
  }

  String _stringOut(String symbol) {
    final out = malloc<ffi.Pointer<Utf8>>();
    try {
      final rc = _lib.lookupFunction<_ListNative, _ListDart>(symbol)(out);
      if (rc != 0) {
        throw StateError('$symbol gagal (kode $rc)');
      }
      final value = out.value.toDartString();
      _free(out.value);
      return value;
    } finally {
      malloc.free(out);
    }
  }

  void _callWithString(String symbol, String value) {
    final p = value.toNativeUtf8();
    try {
      final rc = _lib.lookupFunction<_CodeNative, _CodeDart>(symbol)(p);
      if (rc != 0) {
        throw StateError('$symbol gagal (kode $rc)');
      }
    } finally {
      malloc.free(p);
    }
  }

  bool _boolOut(String symbol) {
    final out = malloc<ffi.Int32>();
    try {
      final rc = _lib.lookupFunction<_BoolOutNative, _BoolOutDart>(symbol)(out);
      if (rc != 0) {
        throw StateError('$symbol gagal (kode $rc)');
      }
      return out.value == 1;
    } finally {
      malloc.free(out);
    }
  }

  // -------------------------------------------------------------------------
  // Notes
  // -------------------------------------------------------------------------

  String noteCreate(String title, String content) {
    final t = title.toNativeUtf8();
    final c = content.toNativeUtf8();
    final out = malloc<ffi.Pointer<Utf8>>();
    try {
      final rc =
          _lib.lookupFunction<_CreateNative, _CreateDart>('drople_note_create')(
        t,
        c,
        out,
      );
      if (rc != 0) {
        throw StateError('drople_note_create gagal (kode $rc)');
      }
      final idPtr = out.value;
      final id = idPtr.toDartString();
      _free(idPtr);
      return id;
    } finally {
      malloc.free(t);
      malloc.free(c);
      malloc.free(out);
    }
  }

  ({String title, String content}) noteGet(String id) {
    final idPtr = id.toNativeUtf8();
    final outTitle = malloc<ffi.Pointer<Utf8>>();
    final outContent = malloc<ffi.Pointer<Utf8>>();
    try {
      final rc =
          _lib.lookupFunction<_GetNative, _GetDart>('drople_note_get')(
        idPtr,
        outTitle,
        outContent,
      );
      if (rc != 0) {
        throw StateError('drople_note_get gagal (kode $rc)');
      }
      final title = outTitle.value.toDartString();
      final content = outContent.value.toDartString();
      _free(outTitle.value);
      _free(outContent.value);
      return (title: title, content: content);
    } finally {
      malloc.free(idPtr);
      malloc.free(outTitle);
      malloc.free(outContent);
    }
  }

  void noteUpdate(String id, String title, String content) {
    final i = id.toNativeUtf8();
    final t = title.toNativeUtf8();
    final c = content.toNativeUtf8();
    try {
      final rc =
          _lib.lookupFunction<_UpdateNative, _UpdateDart>('drople_note_update')(
        i,
        t,
        c,
      );
      if (rc != 0) {
        throw StateError('drople_note_update gagal (kode $rc)');
      }
    } finally {
      malloc.free(i);
      malloc.free(t);
      malloc.free(c);
    }
  }

  void noteDelete(String id) {
    final i = id.toNativeUtf8();
    try {
      final rc = _lib.lookupFunction<_DeleteNative, _DeleteDart>(
        'drople_note_delete',
      )(i);
      if (rc != 0) {
        throw StateError('drople_note_delete gagal (kode $rc)');
      }
    } finally {
      malloc.free(i);
    }
  }

  String noteListJson() => _stringOut('drople_note_list');

  void noteSetFavorite(String id, bool favorite) {
    final i = id.toNativeUtf8();
    try {
      final rc = _lib
          .lookupFunction<_FavoriteNative, _FavoriteDart>(
              'drople_note_set_favorite')(i, favorite ? 1 : 0);
      if (rc != 0) {
        throw StateError('drople_note_set_favorite gagal (kode $rc)');
      }
    } finally {
      malloc.free(i);
    }
  }

  // -------------------------------------------------------------------------
  // Sync
  // -------------------------------------------------------------------------

  String noteSyncStatus(String id) {
    final p = id.toNativeUtf8();
    try {
      final out = malloc<ffi.Pointer<Utf8>>();
      try {
        final rc = _lib
            .lookupFunction<_SyncStatusNative, _SyncStatusDart>(
                'drople_note_sync_status')(p, out);
        if (rc != 0) {
          throw StateError('drople_note_sync_status gagal (kode $rc)');
        }
        final value = out.value.toDartString();
        _free(out.value);
        return value;
      } finally {
        malloc.free(out);
      }
    } finally {
      malloc.free(p);
    }
  }

  String notePendingListJson() => _stringOut('drople_note_pending_list');

  void noteApplyDelta(String deltaJson, String localPeerId) {
    final d = deltaJson.toNativeUtf8();
    final p = localPeerId.toNativeUtf8();
    try {
      final rc = _lib
          .lookupFunction<_ApplyDeltaNative, _ApplyDeltaDart>(
              'drople_note_apply_delta')(d, p);
      if (rc != 0) {
        throw StateError('drople_note_apply_delta gagal (kode $rc)');
      }
    } finally {
      malloc.free(d);
      malloc.free(p);
    }
  }

  void noteMarkAllSynced() {
    final rc = _lib.lookupFunction<_NoArgNative, _NoArgDart>(
      'drople_note_mark_all_synced',
    )();
    if (rc != 0) {
      throw StateError('drople_note_mark_all_synced gagal (kode $rc)');
    }
  }

  void noteSyncWithPeer(String peerId) =>
      _callWithString('drople_note_sync_with_peer', peerId);

  // -------------------------------------------------------------------------
  // Network
  // -------------------------------------------------------------------------

  void setDeviceName(String name) =>
      _callWithString('drople_set_device_name', name);

  String localShortCode() => _stringOut('drople_local_short_code');

  int networkStart() =>
      _lib.lookupFunction<_NoArgNative, _NoArgDart>('drople_network_start')();

  int networkStop() =>
      _lib.lookupFunction<_NoArgNative, _NoArgDart>('drople_network_stop')();

  String localPeerId() => _stringOut('drople_local_peer_id');

  String localFingerprint() => _stringOut('drople_local_fingerprint');

  String peersListJson() => _stringOut('drople_peers_list');

  String pairingStart() => _stringOut('drople_pairing_start');

  void pairingConnect(String code) =>
      _callWithString('drople_pairing_connect', code);

  void addRelay(String addr) =>
      _callWithString('drople_network_add_relay', addr);

  // -------------------------------------------------------------------------
  // File Transfer
  // -------------------------------------------------------------------------

  String fileSend(String peerId, String filePath) {
    final p = peerId.toNativeUtf8();
    final f = filePath.toNativeUtf8();
    final out = malloc<ffi.Pointer<Utf8>>();
    try {
      final rc = _lib
          .lookupFunction<_FileSendNative, _FileSendDart>('drople_file_send')(
        p,
        f,
        out,
      );
      if (rc != 0) {
        throw StateError('drople_file_send gagal (kode $rc)');
      }
      final id = out.value.toDartString();
      _free(out.value);
      return id;
    } finally {
      malloc.free(out);
      malloc.free(p);
      malloc.free(f);
    }
  }

  String fileReceive(String peerId, String savePath) {
    final p = peerId.toNativeUtf8();
    final s = savePath.toNativeUtf8();
    final out = malloc<ffi.Pointer<Utf8>>();
    try {
      final rc = _lib
          .lookupFunction<_FileSendNative, _FileSendDart>('drople_file_receive')(
        p,
        s,
        out,
      );
      if (rc != 0) {
        throw StateError('drople_file_receive gagal (kode $rc)');
      }
      final id = out.value.toDartString();
      _free(out.value);
      return id;
    } finally {
      malloc.free(out);
      malloc.free(p);
      malloc.free(s);
    }
  }

  void fileSetReceiveDir(String path) =>
      _callWithString('drople_file_set_receive_dir', path);

  String fileListJson() => _stringOut('drople_file_list');

  String fileTransferStatus(String id) {
    final p = id.toNativeUtf8();
    final out = malloc<ffi.Pointer<Utf8>>();
    try {
      final rc = _lib
          .lookupFunction<_FileStatusNative, _FileStatusDart>(
              'drople_file_transfer_status')(p, out);
      if (rc != 0) {
        throw StateError('drople_file_transfer_status gagal (kode $rc)');
      }
      final value = out.value.toDartString();
      _free(out.value);
      return value;
    } finally {
      malloc.free(out);
      malloc.free(p);
    }
  }

  // -------------------------------------------------------------------------
  // Google Drive & Backup
  // -------------------------------------------------------------------------

  void gdriveSetToken(String accessToken, String refreshToken, int expiresAt) {
    final a = accessToken.toNativeUtf8();
    final r = refreshToken.toNativeUtf8();
    try {
      final rc = _lib
          .lookupFunction<_SetTokenNative, _SetTokenDart>(
              'drople_gdrive_set_token')(a, r, expiresAt);
      if (rc != 0) {
        throw StateError('drople_gdrive_set_token gagal (kode $rc)');
      }
    } finally {
      malloc.free(a);
      malloc.free(r);
    }
  }

  void gdriveSetClient(String clientId, String clientSecret) {
    final c = clientId.toNativeUtf8();
    final s = clientSecret.toNativeUtf8();
    try {
      final rc = _lib
          .lookupFunction<_TwoStringNative, _TwoStringDart>(
              'drople_gdrive_set_client')(c, s);
      if (rc != 0) {
        throw StateError('drople_gdrive_set_client gagal (kode $rc)');
      }
    } finally {
      malloc.free(c);
      malloc.free(s);
    }
  }

  String gdriveClientId() => _stringOut('drople_gdrive_client_id');

  bool gdriveHasClientSecret() =>
      _boolOut('drople_gdrive_has_client_secret');

  void gdriveExchangeCode(
    String code,
    String verifier,
    String redirectUri,
  ) {
    final c = code.toNativeUtf8();
    final v = verifier.toNativeUtf8();
    final r = redirectUri.toNativeUtf8();
    try {
      final rc = _lib
          .lookupFunction<_UpdateNative, _UpdateDart>(
              'drople_gdrive_exchange_code')(c, v, r);
      if (rc != 0) {
        throw StateError('drople_gdrive_exchange_code gagal (kode $rc)');
      }
    } finally {
      malloc.free(c);
      malloc.free(v);
      malloc.free(r);
    }
  }

  bool gdriveIsConnected() => _boolOut('drople_gdrive_is_connected');

  String gdriveBackup() => _stringOut('drople_gdrive_backup');

  String gdriveBackupListJson() => _stringOut('drople_gdrive_backup_list');

  void gdriveRestore(String backupId) =>
      _callWithString('drople_gdrive_restore', backupId);

  void gdriveDelete(String backupId) =>
      _callWithString('drople_gdrive_delete', backupId);

  void gdriveDisconnect() {
    final rc = _lib.lookupFunction<_NoArgNative, _NoArgDart>(
      'drople_gdrive_disconnect',
    )();
    if (rc != 0) {
      throw StateError('drople_gdrive_disconnect gagal (kode $rc)');
    }
  }

  String backupRecoveryKey() => _stringOut('drople_backup_recovery_key');

  void backupSetRecoveryKey(String mnemonic) =>
      _callWithString('drople_backup_set_recovery_key', mnemonic);

  bool backupIsConfigured() => _boolOut('drople_backup_is_configured');
}
