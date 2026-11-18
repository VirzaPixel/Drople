class PeerEntry {
  const PeerEntry({
    required this.id,
    required this.name,
    required this.lastSeen,
    required this.connected,
    this.latencyMs,
    required this.addresses,
    this.fingerprint = '',
    this.code = '',
    this.platform = '',
  });

  final String id;
  final String name;
  final int lastSeen;
  final bool connected;
  final int? latencyMs;
  final List<String> addresses;
  final String fingerprint;
  final String code;
  final String platform;

  factory PeerEntry.fromJson(Map<String, dynamic> json) {
    return PeerEntry(
      id: json['id'] as String? ?? '',
      name: json['name'] as String? ?? 'Unknown',
      lastSeen: (json['last_seen'] as num?)?.toInt() ?? 0,
      connected: json['connected'] as bool? ?? false,
      latencyMs: (json['latency_ms'] as num?)?.toInt(),
      addresses:
          (json['addresses'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          const [],
      fingerprint: json['fingerprint'] as String? ?? '',
      code: json['code'] as String? ?? '',
      platform: json['platform'] as String? ?? '',
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'last_seen': lastSeen,
      'connected': connected,
      'latency_ms': latencyMs,
      'addresses': addresses,
      'fingerprint': fingerprint,
      'code': code,
      'platform': platform,
    };
  }

  String get shortId => id.length > 8 ? id.substring(0, 8) : id;
  String get statusText => connected ? 'Terhubung' : 'Tidak terhubung';
}

/// Ringkasan diagnostik koneksi P2P (panel Wireless Debugging).
class NetworkDiagnostics {
  const NetworkDiagnostics({
    required this.running,
    required this.peerId,
    required this.code,
    required this.fingerprint,
    required this.listenAddrs,
    required this.peers,
  });

  final bool running;
  final String peerId;
  final String code;
  final String fingerprint;
  final List<String> listenAddrs;
  final List<PeerEntry> peers;

  factory NetworkDiagnostics.fromJson(Map<String, dynamic> json) {
    return NetworkDiagnostics(
      running: json['running'] as bool? ?? false,
      peerId: json['peer_id'] as String? ?? '',
      code: json['code'] as String? ?? '',
      fingerprint: json['fingerprint'] as String? ?? '',
      listenAddrs:
          (json['listen_addrs'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          const [],
      peers:
          (json['peers'] as List<dynamic>?)
              ?.map((e) => PeerEntry.fromJson(e as Map<String, dynamic>))
              .toList() ??
          const [],
    );
  }
}
