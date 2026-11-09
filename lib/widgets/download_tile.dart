import 'package:flutter/material.dart';
import 'package:theme/theme.dart';

import '../models/download_item.dart';
import '../utils/file_kind.dart';
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

  (UiStatus, String) get _statusInfo => switch (item.status) {
    DownloadStatus.queued => (UiStatus.neutral, 'Queued'),
    DownloadStatus.resolving => (UiStatus.info, 'Resolving'),
    DownloadStatus.downloading => (UiStatus.info, 'Downloading'),
    DownloadStatus.paused => (UiStatus.warning, 'Paused'),
    DownloadStatus.completed => (UiStatus.success, 'Completed'),
    DownloadStatus.failed => (UiStatus.danger, 'Failed'),
    DownloadStatus.canceled => (UiStatus.neutral, 'Canceled'),
  };

  @override
  Widget build(BuildContext context) {
    final (status, label) = _statusInfo;
    final isActive = item.status == DownloadStatus.downloading || item.status == DownloadStatus.resolving;
    final isOpenable = item.status == DownloadStatus.completed;
    final kind = fileKindFor(item.mimeType, item.fileName);
    final kindStyle = FileKindStyle.of(kind);
    final text = context.text;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: UiSpace.lg, vertical: 6),
      child: UiCard(
        padding: const EdgeInsets.all(14),
        onTap: isOpenable ? onOpen : null,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                UiIconBox(kindStyle.icon, color: kindStyle.color, size: 44),
                const SizedBox(width: UiSpace.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(item.fileName, maxLines: 1, overflow: TextOverflow.ellipsis, style: text.titleSmall),
                      const SizedBox(height: 3),
                      Text(item.url, maxLines: 1, overflow: TextOverflow.ellipsis, style: text.bodySmall),
                    ],
                  ),
                ),
                const SizedBox(width: UiSpace.sm),
                UiStatusPill(label, status: status),
              ],
            ),
            if (isActive) ...[
              const SizedBox(height: UiSpace.md),
              UiProgressBar(item.totalBytes > 0 ? item.progress : null),
              const SizedBox(height: UiSpace.xs),
              Text(
                item.totalBytes > 0
                    ? '${formatBytes(item.receivedBytes)} / ${formatBytes(item.totalBytes)}'
                    : formatBytes(item.receivedBytes),
                style: text.bodySmall,
              ),
            ],
            if (item.status == DownloadStatus.failed && item.errorMessage != null) ...[
              const SizedBox(height: 6),
              Text(item.errorMessage!, style: text.bodySmall?.copyWith(color: context.colors.danger)),
            ],
            if (item.status == DownloadStatus.completed) ...[
              const SizedBox(height: UiSpace.xs),
              Text(formatBytes(item.totalBytes), style: text.bodySmall),
            ],
            const SizedBox(height: 6),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                if (isActive)
                  UiButton(
                    'Cancel',
                    variant: UiButtonVariant.ghost,
                    size: UiSize.sm,
                    icon: Icons.close,
                    onPressed: onCancel,
                  ),
                if (item.status == DownloadStatus.failed || item.status == DownloadStatus.canceled)
                  UiButton(
                    'Retry',
                    variant: UiButtonVariant.ghost,
                    size: UiSize.sm,
                    icon: Icons.refresh,
                    onPressed: onRetry,
                  ),
                if (!isActive)
                  UiButton(
                    'Delete',
                    variant: UiButtonVariant.ghost,
                    size: UiSize.sm,
                    icon: Icons.delete_outline,
                    onPressed: onDelete,
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
