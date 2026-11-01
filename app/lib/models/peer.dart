class PeerEntry {
  const PeerEntry({
    required this.id,
    required this.name,
    required this.lastSeen,
    required this.connected,
    this.latencyMs,
    required this.addresses,
    this.fingerprint = '',
  });

  final String id;
  final String name;
  final int lastSeen;
  final bool connected;
  final int? latencyMs;
  final List<String> addresses;
  final String fingerprint;

  factory PeerEntry.fromJson(Map<String, dynamic> json) {
    return PeerEntry(
      id: json['id'] as String? ?? '',
      name: json['name'] as String? ?? 'Unknown',
      lastSeen: (json['last_seen'] as num?)?.toInt() ?? 0,
      connected: json['connected'] as bool? ?? false,
      latencyMs: (json['latency_ms'] as num?)?.toInt(),
      addresses: (json['addresses'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          const [],
      fingerprint: json['fingerprint'] as String? ?? '',
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
    };
  }

  String get shortId => id.length > 8 ? id.substring(0, 8) : id;
  String get statusText => connected ? 'Terhubung' : 'Tidak terhubung';
}
