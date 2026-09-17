enum DownloadStatus {
  queued,
  resolving,
  downloading,
  paused,
  completed,
  failed,
  canceled,
}

class DownloadItem {
  const DownloadItem({
    required this.id,
    required this.url,
    required this.fileName,
    required this.filePath,
    required this.status,
    required this.createdAt,
    this.mimeType,
    this.totalBytes = 0,
    this.receivedBytes = 0,
    this.errorMessage,
  });

  final String id;
  final String url;
  final String fileName;
  final String filePath;
  final DownloadStatus status;
  final DateTime createdAt;
  final String? mimeType;
  final int totalBytes;
  final int receivedBytes;
  final String? errorMessage;

  double get progress => totalBytes > 0 ? receivedBytes / totalBytes : 0;

  DownloadItem copyWith({
    String? fileName,
    String? filePath,
    DownloadStatus? status,
    String? mimeType,
    int? totalBytes,
    int? receivedBytes,
    String? errorMessage,
  }) {
    return DownloadItem(
      id: id,
      url: url,
      fileName: fileName ?? this.fileName,
      filePath: filePath ?? this.filePath,
      status: status ?? this.status,
      createdAt: createdAt,
      mimeType: mimeType ?? this.mimeType,
      totalBytes: totalBytes ?? this.totalBytes,
      receivedBytes: receivedBytes ?? this.receivedBytes,
      errorMessage: errorMessage,
    );
  }

  Map<String, Object?> toMap() => {
    'id': id,
    'url': url,
    'fileName': fileName,
    'filePath': filePath,
    'status': status.name,
    'createdAt': createdAt.toIso8601String(),
    'mimeType': mimeType,
    'totalBytes': totalBytes,
    'receivedBytes': receivedBytes,
    'errorMessage': errorMessage,
  };

  factory DownloadItem.fromMap(Map<String, Object?> map) => DownloadItem(
    id: map['id'] as String,
    url: map['url'] as String,
    fileName: map['fileName'] as String,
    filePath: map['filePath'] as String,
    status: DownloadStatus.values.byName(map['status'] as String),
    createdAt: DateTime.parse(map['createdAt'] as String),
    mimeType: map['mimeType'] as String?,
    totalBytes: map['totalBytes'] as int? ?? 0,
    receivedBytes: map['receivedBytes'] as int? ?? 0,
    errorMessage: map['errorMessage'] as String?,
  );
}
