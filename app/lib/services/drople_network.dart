import 'dart:convert';
import 'dart:io';

import 'package:device_info_plus/device_info_plus.dart';

import '../ffi/drople_bindings.dart';
import '../models/peer.dart';

/// Wrapper jaringan P2P. Satu instance global dipakai seluruh aplikasi agar
/// koneksi peer tidak terputus saat berpindah halaman.
class DropleNetwork {
  DropleNetwork({DropleBindings? bindings}) : _injected = bindings;

  static final DropleNetwork shared = DropleNetwork();

  final DropleBindings? _injected;
  late final DropleBindings _bindings = _injected ?? DropleBindings.instance;

  static bool _started = false;
  static String? _deviceName;

  bool get isStarted => _started;
  String? get deviceName => _deviceName;

  Future<void> start({String? name}) async {
    if (_started) return;
    final resolved = name ?? await _detectDeviceName();
    _deviceName = resolved;
    try {
      _bindings.setDeviceName(resolved);
    } catch (_) {}
    final rc = _bindings.networkStart();
    if (rc != 0) {
      throw StateError('drople_network_start gagal (kode $rc)');
    }
    _started = true;
  }

  Future<void> stop() async {
    if (!_started) return;
    _bindings.networkStop();
    _started = false;
  }

  Future<String> _detectDeviceName() async {
    try {
      final info = DeviceInfoPlugin();
      if (Platform.isAndroid) {
        final android = await info.androidInfo;
        return _titleCase('${android.manufacturer} ${android.model}');
      }
      if (Platform.isIOS) {
        final ios = await info.iosInfo;
        return ios.name.trim().isEmpty ? 'iPhone' : ios.name.trim();
      }
      if (Platform.isMacOS) {
        final mac = await info.macOsInfo;
        return mac.computerName.trim().isEmpty
            ? 'Mac'
            : mac.computerName.trim();
      }
      if (Platform.isWindows) {
        final win = await info.windowsInfo;
        return win.computerName.trim().isEmpty
            ? 'Windows'
            : win.computerName.trim();
      }
      if (Platform.isLinux) {
        final linux = await info.linuxInfo;
        final pretty = linux.prettyName.trim();
        if (pretty.isNotEmpty) return pretty;
      }
    } catch (_) {}
    final host = Platform.localHostname.trim();
    return host.isEmpty ? 'Perangkat Drople' : host;
  }

  String _titleCase(String value) {
    final cleaned = value.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (cleaned.isEmpty) return 'Perangkat Drople';
    return cleaned
        .split(' ')
        .map((w) => w.isEmpty ? w : '${w[0].toUpperCase()}${w.substring(1)}')
        .join(' ');
  }

  String localPeerId() => _bindings.localPeerId();

  String localFingerprint() => _bindings.localFingerprint();

  String localShortCode() => _bindings.localShortCode();

  List<PeerEntry> listPeers() {
    final data = jsonDecode(_bindings.peersListJson()) as List<dynamic>;
    return data
        .map((e) => PeerEntry.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<String> startPairing() async => _bindings.pairingStart();

  Future<void> connectPairing(String code) async {
    _bindings.pairingConnect(code);
  }

  List<({String id, String name})> pendingApprovals() {
    final data = jsonDecode(_bindings.pendingApprovalsJson()) as List<dynamic>;
    return data.map((item) {
      final request = item as Map<String, dynamic>;
      return (
        id: request['id'] as String,
        name: request['name'] as String? ?? '',
      );
    }).toList();
  }

  void approvePairing(String peerId) => _bindings.approvePairing(peerId);

  void rejectPairing(String peerId) => _bindings.rejectPairing(peerId);

  void disconnectPeer(String peerId) => _bindings.disconnectPeer(peerId);

  List<({String peerId, bool accepted})> takePairingNotifications() {
    final data =
        jsonDecode(_bindings.pairingNotificationsJson()) as List<dynamic>;
    return data.map((item) {
      final notification = item as Map<String, dynamic>;
      return (
        peerId: notification['peer_id'] as String,
        accepted: notification['accepted'] as bool,
      );
    }).toList();
  }

  Future<void> addRelay(String addr) async {
    _bindings.addRelay(addr);
  }
}
