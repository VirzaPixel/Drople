class FileTransferItem {
  const FileTransferItem({
    required this.id,
    required this.peerId,
    required this.fileName,
    required this.fileSize,
    required this.fileHash,
    required this.status,
    required this.direction,
    required this.createdAt,
    this.completedAt,
    this.localPath,
    this.progress = 0,
  });

  final String id;
  final String peerId;
  final String fileName;
  final int fileSize;
  final String fileHash;
  final String status;
  final String direction;
  final int createdAt;
  final int? completedAt;
  final String? localPath;
  final int progress;

  factory FileTransferItem.fromJson(Map<String, dynamic> json) {
    return FileTransferItem(
      id: json['id'] as String,
      peerId: json['peer_id'] as String? ?? '',
      fileName: json['file_name'] as String? ?? '',
      fileSize: (json['file_size'] as num?)?.toInt() ?? 0,
      fileHash: json['file_hash'] as String? ?? '',
      status: json['status'] as String? ?? 'pending',
      direction: json['direction'] as String? ?? 'send',
      createdAt: (json['created_at'] as num?)?.toInt() ?? 0,
      completedAt: (json['completed_at'] as num?)?.toInt(),
      localPath: json['local_path'] as String?,
      progress: (json['progress'] as num?)?.toInt() ?? 0,
    );
  }

  bool get isSend => direction == 'send';
  bool get isCompleted => status == 'completed';
  bool get isFailed => status == 'failed';
  bool get isCancelled => status == 'cancelled';
  bool get isActive => status == 'active' || status == 'pending';

  double get percent {
    if (fileSize <= 0) return 0.0;
    final p = progress / fileSize;
    if (p < 0.0) return 0.0;
    if (p > 1.0) return 1.0;
    return p;
  }
}

/// Permintaan transfer file yang menunggu persetujuan pengguna.
class PendingFileOffer {
  const PendingFileOffer({
    required this.transferId,
    required this.peerId,
    required this.peerName,
    required this.fileName,
    required this.fileSize,
    required this.fileHash,
    required this.createdAt,
  });

  final String transferId;
  final String peerId;
  final String peerName;
  final String fileName;
  final int fileSize;
  final String fileHash;
  final int createdAt;

  factory PendingFileOffer.fromJson(Map<String, dynamic> json) {
    return PendingFileOffer(
      transferId: json['transfer_id'] as String? ?? '',
      peerId: json['peer_id'] as String? ?? '',
      peerName: json['peer_name'] as String? ?? '',
      fileName: json['file_name'] as String? ?? '',
      fileSize: (json['file_size'] as num?)?.toInt() ?? 0,
      fileHash: json['file_hash'] as String? ?? '',
      createdAt: (json['created_at'] as num?)?.toInt() ?? 0,
    );
  }
}
