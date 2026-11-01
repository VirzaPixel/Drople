class NoteSummary {
  const NoteSummary({
    required this.id,
    required this.title,
    required this.updatedAt,
    required this.isFavorite,
    this.syncStatus = 'synced',
    this.preview = '',
  });

  final String id;
  final String title;
  final int updatedAt;
  final int isFavorite;
  final String syncStatus;
  final String preview;

  factory NoteSummary.fromJson(Map<String, dynamic> json) {
    return NoteSummary(
      id: json['id'] as String,
      title: json['title'] as String,
      updatedAt: (json['updated_at'] as num).toInt(),
      isFavorite: (json['is_favorite'] as num).toInt(),
      syncStatus: json['sync_status'] as String? ?? 'synced',
      preview: json['preview'] as String? ?? '',
    );
  }

  bool get isSynced => syncStatus == 'synced';
  bool get isPending => syncStatus == 'pending';
  bool get isConflict => syncStatus == 'conflict';
}
