import 'package:flutter/material.dart';
import 'package:theme/theme.dart';

import '../models/download_item.dart';
import '../utils/formatters.dart';

class DownloadTile extends StatelessWidget {
  const DownloadTile({
    super.key,
    required this.item,
    required this.onOpen,
    required this.onCancel,
    required this.onRetry,
    required this.onDelete,
  });

  final DownloadItem item;
  final VoidCallback onOpen;
  final VoidCallback onCancel;
  final VoidCallback onRetry;
  final VoidCallback onDelete;

  IconData get _fileIcon {
    final mime = item.mimeType ?? '';
    if (mime.startsWith('image/')) return Icons.image_outlined;
    if (mime.startsWith('video/')) return Icons.movie_outlined;
    if (mime.startsWith('audio/')) return Icons.audiotrack_outlined;
    if (mime.contains('pdf')) return Icons.picture_as_pdf_outlined;
    if (mime.contains('zip') || mime.contains('compressed')) return Icons.folder_zip_outlined;
    return Icons.insert_drive_file_outlined;
  }

  (ThemeStatus, String) get _statusInfo => switch (item.status) {
    DownloadStatus.queued => (ThemeStatus.neutral, 'Queued'),
    DownloadStatus.resolving => (ThemeStatus.info, 'Resolving'),
    DownloadStatus.downloading => (ThemeStatus.info, 'Downloading'),
    DownloadStatus.paused => (ThemeStatus.warning, 'Paused'),
    DownloadStatus.completed => (ThemeStatus.success, 'Completed'),
    DownloadStatus.failed => (ThemeStatus.error, 'Failed'),
    DownloadStatus.canceled => (ThemeStatus.neutral, 'Canceled'),
  };

  @override
  Widget build(BuildContext context) {
    final (status, label) = _statusInfo;
    final isActive =
        item.status == DownloadStatus.downloading ||
        item.status == DownloadStatus.resolving;

    return ThemeCard(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: item.status == DownloadStatus.completed ? onOpen : null,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(_fileIcon, size: 28),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          item.fileName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.titleSmall,
                        ),
                        const SizedBox(height: 2),
                        Text(
                          item.url,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  ThemeStatusPill(label: label, status: status),
                ],
              ),
              if (isActive) ...[
                const SizedBox(height: 10),
                ThemeProgressIndicator(
                  type: ThemeProgressIndicatorType.linear,
                  value: item.totalBytes > 0 ? item.progress : null,
                ),
                const SizedBox(height: 4),
                Text(
                  item.totalBytes > 0
                      ? '${formatBytes(item.receivedBytes)} / ${formatBytes(item.totalBytes)}'
                      : formatBytes(item.receivedBytes),
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
              if (item.status == DownloadStatus.failed &&
                  item.errorMessage != null) ...[
                const SizedBox(height: 6),
                Text(
                  item.errorMessage!,
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.error,
                    fontSize: 12,
                  ),
                ),
              ],
              if (item.status == DownloadStatus.completed) ...[
                const SizedBox(height: 4),
                Text(
                  formatBytes(item.totalBytes),
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  if (isActive)
                    TextButton.icon(
                      onPressed: onCancel,
                      icon: const Icon(Icons.close, size: 18),
                      label: const Text('Cancel'),
                    ),
                  if (item.status == DownloadStatus.failed ||
                      item.status == DownloadStatus.canceled)
                    TextButton.icon(
                      onPressed: onRetry,
                      icon: const Icon(Icons.refresh, size: 18),
                      label: const Text('Retry'),
                    ),
                  if (!isActive)
                    TextButton.icon(
                      onPressed: onDelete,
                      icon: const Icon(Icons.delete_outline, size: 18),
                      label: const Text('Delete'),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
