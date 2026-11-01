import 'dart:convert';

import '../ffi/drople_bindings.dart';
import '../models/peer.dart';

/// Wrapper tingkat tinggi untuk fungsi jaringan P2P Core Rust via FFI.
class DropleNetwork {
  DropleNetwork({DropleBindings? bindings}) : _injected = bindings;

  final DropleBindings? _injected;
  late final DropleBindings _bindings = _injected ?? DropleBindings.instance;

  bool _started = false;

  /// Memulai node P2P (mDNS + Noise + TCP/Relay).
  Future<void> start() async {
    if (_started) return;
    final rc = _bindings.networkStart();
    if (rc != 0) {
      throw StateError('drople_network_start gagal (kode $rc)');
    }
    _started = true;
  }

  /// Menghentikan node P2P.
  Future<void> stop() async {
    if (!_started) return;
    _bindings.networkStop();
    _started = false;
  }

  /// Mengembalikan Peer ID lokal (base58).
  String localPeerId() => _bindings.localPeerId();

  /// Mengembalikan fingerprint SHA-256 lokal yang mudah dibaca.
  String localFingerprint() => _bindings.localFingerprint();

  /// Mengembalikan daftar peer yang ditemukan/dihubungkan (JSON).
  List<PeerEntry> listPeers() {
    final data = jsonDecode(_bindings.peersListJson()) as List<dynamic>;
    return data
        .map((e) => PeerEntry.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// Membuat pairing code (prefix `DRO1:`) untuk ditampilkan sebagai QR/teks.
  Future<String> startPairing() async {
    return _bindings.pairingStart();
  }

  /// Terhubung ke peer menggunakan pairing code.
  Future<void> connectPairing(String code) async {
    _bindings.pairingConnect(code);
  }

  /// Menambahkan relay server (multiaddr lengkap dengan `/p2p/<peerid>`).
  Future<void> addRelay(String addr) async {
    _bindings.addRelay(addr);
  }
}
