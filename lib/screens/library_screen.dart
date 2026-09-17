import 'dart:async';

import 'package:flutter/material.dart';
import 'package:open_filex/open_filex.dart';
import 'package:theme/theme.dart';

import '../models/download_item.dart';
import '../services/download_manager.dart';
import '../services/link_resolver.dart';
import '../services/share_intent_service.dart';
import '../widgets/download_tile.dart';
import '../widgets/share_confirm_sheet.dart';

class LibraryScreen extends StatefulWidget {
  const LibraryScreen({super.key});

  @override
  State<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends State<LibraryScreen> {
  List<DownloadItem> _items = [];
  StreamSubscription<List<DownloadItem>>? _itemsSub;
  StreamSubscription<String>? _shareSub;

  @override
  void initState() {
    super.initState();
    _items = DownloadManager.instance.items;
    _itemsSub = DownloadManager.instance.itemsStream.listen(
      (items) => setState(() => _items = items),
    );
    _shareSub = ShareIntentService.instance.sharedText.listen(
      _handleSharedText,
    );
  }

  @override
  void dispose() {
    _itemsSub?.cancel();
    _shareSub?.cancel();
    super.dispose();
  }

  Future<void> _handleSharedText(String sharedText) async {
    final url = extractUrl(sharedText);
    if (url == null) {
      if (mounted) {
        Notify.warning(context, 'No downloadable link found in the shared content.');
      }
      return;
    }
    if (!mounted) return;
    final confirmed = await ShareConfirmSheet.show(context, url);
    if (confirmed) {
      unawaited(DownloadManager.instance.startFromSharedUrl(url));
    }
  }

  Future<void> _openFile(DownloadItem item) async {
    final result = await OpenFilex.open(item.filePath);
    if (result.type != ResultType.done && mounted) {
      Notify.error(context, 'Could not open file: ${result.message}');
    }
  }

  Future<void> _confirmDelete(DownloadItem item) async {
    final confirmed = await ThemeConfirmDialog.show(
      context,
      title: 'Delete download?',
      content:
          '${item.fileName} will be removed from LinkDrop\'s library and deleted from storage.',
      confirmLabel: 'Delete',
      isDestructive: true,
    );
    if (confirmed) {
      await DownloadManager.instance.deleteCompletedFile(item.id);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: const ThemeAppBar(title: 'LinkDrop'),
      body: _items.isEmpty
          ? ThemeEmptyState(
              title: 'No downloads yet',
              subtitle:
                  'Share a link to any file from another app and it will show up here.',
              icon: Icons.download_outlined,
            )
          : ListView.builder(
              padding: const EdgeInsets.only(top: 8, bottom: 24),
              itemCount: _items.length,
              itemBuilder: (context, index) {
                final item = _items[index];
                return DownloadTile(
                  item: item,
                  onOpen: () => _openFile(item),
                  onCancel: () => DownloadManager.instance.cancel(item.id),
                  onRetry: () => DownloadManager.instance.retry(item.id),
                  onDelete: () => _confirmDelete(item),
                );
              },
            ),
    );
  }
}
