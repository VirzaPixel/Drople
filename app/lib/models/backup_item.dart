class BackupItem {
  const BackupItem({
    required this.id,
    required this.createdAt,
    required this.size,
    required this.status,
    this.localChecksum,
  });

  final String id;
  final int createdAt;
  final int size;
  final String status;
  final String? localChecksum;

  factory BackupItem.fromJson(Map<String, dynamic> json) {
    return BackupItem(
      id: json['id'] as String,
      createdAt: (json['created_at'] as num?)?.toInt() ?? 0,
      size: (json['size'] as num?)?.toInt() ?? 0,
      status: json['status'] as String? ?? 'completed',
      localChecksum: json['local_checksum'] as String?,
    );
  }

  DateTime get date => DateTime.fromMillisecondsSinceEpoch(createdAt);

  String get sizeFormatted {
    if (size < 1024) return '$size B';
    if (size < 1024 * 1024) {
      return '${(size / 1024).toStringAsFixed(1)} KB';
    }
    return '${(size / (1024 * 1024)).toStringAsFixed(2)} MB';
  }
}
