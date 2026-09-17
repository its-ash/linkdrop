import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

import '../models/download_item.dart';
import 'database_service.dart';
import 'link_resolver.dart';

class DownloadManager {
  DownloadManager._()
    : _dio = Dio(
        BaseOptions(
          connectTimeout: const Duration(seconds: 20),
          receiveTimeout: const Duration(minutes: 30),
        ),
      ) {
    _resolver = LinkResolver(_dio);
  }

  static final DownloadManager instance = DownloadManager._();

  final Dio _dio;
  late final LinkResolver _resolver;
  final Map<String, CancelToken> _cancelTokens = {};

  final _itemsController = StreamController<List<DownloadItem>>.broadcast();
  Stream<List<DownloadItem>> get itemsStream => _itemsController.stream;

  List<DownloadItem> _items = [];
  List<DownloadItem> get items => List.unmodifiable(_items);

  Future<void> init() async {
    _items = await DatabaseService.instance.all();
    _emit();
  }

  void _emit() => _itemsController.add(List.unmodifiable(_items));

  void _update(DownloadItem item) {
    final idx = _items.indexWhere((e) => e.id == item.id);
    if (idx >= 0) {
      _items[idx] = item;
    } else {
      _items.insert(0, item);
    }
    _emit();
    unawaited(DatabaseService.instance.upsert(item));
  }

  /// Kicks off resolution + download for a raw shared URL string.
  Future<void> startFromSharedUrl(String url) async {
    final id = const Uuid().v4();
    var item = DownloadItem(
      id: id,
      url: url,
      fileName: _fileNameGuess(url),
      filePath: '',
      status: DownloadStatus.resolving,
      createdAt: DateTime.now(),
    );
    _update(item);

    try {
      final resolved = await _resolver.resolve(url);
      final dir = await _downloadsDirectory();
      final targetPath = await _uniquePath(dir, resolved.fileName);

      item = item.copyWith(
        fileName: p.basename(targetPath),
        filePath: targetPath,
        mimeType: resolved.mimeType,
        totalBytes: resolved.totalBytes,
        status: DownloadStatus.downloading,
      );
      _update(item);

      final cancelToken = CancelToken();
      _cancelTokens[id] = cancelToken;

      await _dio.download(
        resolved.url,
        targetPath,
        cancelToken: cancelToken,
        onReceiveProgress: (received, total) {
          item = item.copyWith(
            receivedBytes: received,
            totalBytes: total > 0 ? total : item.totalBytes,
          );
          _update(item);
        },
      );

      item = item.copyWith(status: DownloadStatus.completed);
      _update(item);
    } on LinkResolveException catch (e) {
      item = item.copyWith(
        status: DownloadStatus.failed,
        errorMessage: e.message,
      );
      _update(item);
    } on DioException catch (e) {
      final canceled = e.type == DioExceptionType.cancel;
      item = item.copyWith(
        status: canceled ? DownloadStatus.canceled : DownloadStatus.failed,
        errorMessage: canceled
            ? null
            : 'Download failed: ${e.message ?? e.type.name}',
      );
      _update(item);
    } catch (e) {
      item = item.copyWith(
        status: DownloadStatus.failed,
        errorMessage: e.toString(),
      );
      _update(item);
    } finally {
      _cancelTokens.remove(id);
    }
  }

  void cancel(String id) {
    _cancelTokens[id]?.cancel();
  }

  Future<void> retry(String id) async {
    final item = _items.firstWhere((e) => e.id == id);
    await startFromSharedUrl(item.url);
    await remove(id);
  }

  Future<void> remove(String id) async {
    cancel(id);
    final item = _items.firstWhere(
      (e) => e.id == id,
      orElse: () => DownloadItem(
        id: id,
        url: '',
        fileName: '',
        filePath: '',
        status: DownloadStatus.canceled,
        createdAt: DateTime.now(),
      ),
    );
    if (item.filePath.isNotEmpty) {
      final file = File(item.filePath);
      if (await file.exists() && item.status != DownloadStatus.completed) {
        await file.delete();
      }
    }
    _items.removeWhere((e) => e.id == id);
    _emit();
    await DatabaseService.instance.delete(id);
  }

  Future<void> deleteCompletedFile(String id) async {
    final item = _items.firstWhere((e) => e.id == id);
    final file = File(item.filePath);
    if (await file.exists()) await file.delete();
    _items.removeWhere((e) => e.id == id);
    _emit();
    await DatabaseService.instance.delete(id);
  }

  Future<Directory> _downloadsDirectory() async {
    Directory dir;
    if (Platform.isAndroid) {
      dir = Directory('/storage/emulated/0/Download/LinkDrop');
      try {
        if (!await dir.exists()) await dir.create(recursive: true);
      } catch (_) {
        dir = await getApplicationDocumentsDirectory();
        dir = Directory(p.join(dir.path, 'LinkDrop'));
        if (!await dir.exists()) await dir.create(recursive: true);
      }
    } else {
      final base = await getApplicationDocumentsDirectory();
      dir = Directory(p.join(base.path, 'LinkDrop'));
      if (!await dir.exists()) await dir.create(recursive: true);
    }
    return dir;
  }

  Future<String> _uniquePath(Directory dir, String fileName) async {
    var candidate = p.join(dir.path, fileName);
    if (!await File(candidate).exists()) return candidate;

    final ext = p.extension(fileName);
    final base = p.basenameWithoutExtension(fileName);
    var counter = 1;
    while (await File(candidate).exists()) {
      candidate = p.join(dir.path, '$base ($counter)$ext');
      counter++;
    }
    return candidate;
  }

  String _fileNameGuess(String url) {
    final uri = Uri.tryParse(url);
    final segments =
        uri?.pathSegments.where((s) => s.isNotEmpty).toList() ?? [];
    return segments.isNotEmpty ? segments.last : 'download';
  }
}
