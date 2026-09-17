import 'package:flutter/material.dart';
import 'package:theme/theme.dart';

import '../models/download_item.dart';
import '../utils/file_kind.dart';
import '../utils/formatters.dart';

class DownloadTile extends StatefulWidget {
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

  @override
  State<DownloadTile> createState() => _DownloadTileState();
}

class _DownloadTileState extends State<DownloadTile> {
  double _pressScale = 1;

  (ThemeStatus, String) get _statusInfo => switch (widget.item.status) {
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
    final item = widget.item;
    final (status, label) = _statusInfo;
    final isActive = item.status == DownloadStatus.downloading || item.status == DownloadStatus.resolving;
    final isOpenable = item.status == DownloadStatus.completed;
    final kind = fileKindFor(item.mimeType, item.fileName);
    final kindStyle = FileKindStyle.of(kind);

    return AnimatedScale(
      scale: _pressScale,
      duration: const Duration(milliseconds: 120),
      curve: Curves.easeOut,
      child: ThemeCard(
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: isOpenable ? widget.onOpen : null,
          onTapDown: isOpenable ? (_) => setState(() => _pressScale = 0.98) : null,
          onTapCancel: () => setState(() => _pressScale = 1),
          onTapUp: (_) => setState(() => _pressScale = 1),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: kindStyle.color.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(kindStyle.icon, color: kindStyle.color, size: 22),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            item.fileName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(
                              context,
                            ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600),
                          ),
                          const SizedBox(height: 3),
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
                  const SizedBox(height: 12),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(999),
                    child: TweenAnimationBuilder<double>(
                      tween: Tween(end: item.totalBytes > 0 ? item.progress : 0),
                      duration: const Duration(milliseconds: 300),
                      curve: Curves.easeOut,
                      builder: (context, value, _) => ThemeProgressIndicator(
                        type: ThemeProgressIndicatorType.linear,
                        value: item.totalBytes > 0 ? value : null,
                      ),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    item.totalBytes > 0
                        ? '${formatBytes(item.receivedBytes)} / ${formatBytes(item.totalBytes)}'
                        : formatBytes(item.receivedBytes),
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
                if (item.status == DownloadStatus.failed && item.errorMessage != null) ...[
                  const SizedBox(height: 6),
                  Text(
                    item.errorMessage!,
                    style: TextStyle(color: Theme.of(context).colorScheme.error, fontSize: 12),
                  ),
                ],
                if (item.status == DownloadStatus.completed) ...[
                  const SizedBox(height: 4),
                  Text(formatBytes(item.totalBytes), style: Theme.of(context).textTheme.bodySmall),
                ],
                const SizedBox(height: 6),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    if (isActive)
                      TextButton.icon(
                        onPressed: widget.onCancel,
                        icon: const Icon(Icons.close, size: 18),
                        label: const Text('Cancel'),
                      ),
                    if (item.status == DownloadStatus.failed || item.status == DownloadStatus.canceled)
                      TextButton.icon(
                        onPressed: widget.onRetry,
                        icon: const Icon(Icons.refresh, size: 18),
                        label: const Text('Retry'),
                      ),
                    if (!isActive)
                      TextButton.icon(
                        onPressed: widget.onDelete,
                        icon: const Icon(Icons.delete_outline, size: 18),
                        label: const Text('Delete'),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
