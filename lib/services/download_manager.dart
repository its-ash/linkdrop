import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

import '../models/download_item.dart';
import 'database_service.dart';
import 'instagram_extractor.dart';
import 'instagram_webview.dart';
import 'link_resolver.dart';
import 'parallel_downloader.dart';
import '../utils/share_parser.dart';

class DownloadManager {
  DownloadManager._()
    : _dio = Dio(
        BaseOptions(
          connectTimeout: const Duration(seconds: 20),
          // Per read, not for the whole file: a stalled connection is retried.
          receiveTimeout: const Duration(seconds: 30),
        ),
      ) {
    _resolver = LinkResolver(_dio);
    _downloader = ParallelDownloader(_dio);
    InstagramExtractor.instance.browserFetch = fetchWithWebView;
  }

  static final DownloadManager instance = DownloadManager._();

  final Dio _dio;
  late final LinkResolver _resolver;
  late final ParallelDownloader _downloader;
  final Map<String, CancelToken> _cancelTokens = {};
  final Set<String> _activeDownloads = {};
  final Map<String, DateTime> _lastProgressSave = {};

  final _itemsController = StreamController<List<DownloadItem>>.broadcast();
  Stream<List<DownloadItem>> get itemsStream => _itemsController.stream;

  List<DownloadItem> _items = [];
  List<DownloadItem> get items => List.unmodifiable(_items);

  Future<void> init() async {
    _items = await DatabaseService.instance.all();
    for (var i = 0; i < _items.length; i++) {
      final item = _items[i];
      if (item.status == DownloadStatus.queued ||
          item.status == DownloadStatus.resolving ||
          item.status == DownloadStatus.downloading) {
        if (item.filePath.isNotEmpty) {
          await _deleteIfExists('${item.filePath}.part');
        }
        final updated = item.copyWith(status: DownloadStatus.failed, errorMessage: 'Interrupted');
        _items[i] = updated;
        await DatabaseService.instance.upsert(updated);
      }
    }
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

  /// Progress ticks arrive many times a second from several connections:
  /// refresh the UI at most ~6 times a second and skip the database.
  void _progress(DownloadItem item) {
    final now = DateTime.now();
    final last = _lastProgressSave[item.id];
    if (last != null && now.difference(last) < const Duration(milliseconds: 150)) return;
    _lastProgressSave[item.id] = now;
    final idx = _items.indexWhere((e) => e.id == item.id);
    if (idx < 0) return;
    _items[idx] = item;
    _emit();
  }

  /// True while a download for the same (normalized) link is still running.
  bool isInProgress(String url) {
    final key = normalizeUrl(url);
    return _items.any((e) =>
        (e.status == DownloadStatus.resolving || e.status == DownloadStatus.downloading) &&
        normalizeUrl(e.url) == key);
  }

  /// Kicks off resolution + download for a raw shared URL string.
  Future<void> startFromSharedUrl(String url) async {
    final id = const Uuid().v4();
    final cancelToken = CancelToken();
    _cancelTokens[id] = cancelToken;
    var item = DownloadItem(
      id: id,
      url: url,
      fileName: _fileNameGuess(url),
      filePath: '',
      status: DownloadStatus.resolving,
      createdAt: DateTime.now(),
    );
    _update(item);

    if (isInstagramUrl(url)) {
      await _startInstagram(item, cancelToken);
      return;
    }

    try {
      final resolved = await _resolver.resolve(url);
      if (cancelToken.isCancelled) {
        _cancelTokens.remove(id);
        return;
      }
      final dir = await _downloadsDirectory();
      final targetPath = await _uniquePath(dir, resolved.fileName);
      if (cancelToken.isCancelled) {
        _cancelTokens.remove(id);
        return;
      }
      item = item.copyWith(mimeType: resolved.mimeType, totalBytes: resolved.totalBytes);
      await _download(item, resolved.url, targetPath, cancelToken: cancelToken);
    } on LinkResolveException catch (e) {
      _cancelTokens.remove(id);
      if (!cancelToken.isCancelled) {
        _update(item.copyWith(status: DownloadStatus.failed, errorMessage: e.message));
      }
    } catch (e) {
      _cancelTokens.remove(id);
      if (!cancelToken.isCancelled) {
        _update(item.copyWith(status: DownloadStatus.failed, errorMessage: e.toString()));
      }
    }
  }

  /// Instagram post/reel: find the media behind the post, then download each
  /// file (a carousel becomes one library entry per slide).
  Future<void> _startInstagram(DownloadItem item, CancelToken cancelToken) async {
    final List<InstagramMedia> media;
    final InstagramPost post;
    try {
      post = await InstagramExtractor.instance.resolvePost(item.url);
      if (cancelToken.isCancelled) {
        _cancelTokens.remove(item.id);
        return;
      }
      final all = await InstagramExtractor.instance.extractMedia(post);
      final slide = instagramSlideIndex(item.url);
      media = slide != null && slide <= all.length && all.length > 1 ? [all[slide - 1]] : all;
    } on InstagramExtractException catch (e) {
      _cancelTokens.remove(item.id);
      if (!cancelToken.isCancelled) {
        _update(item.copyWith(status: DownloadStatus.failed, errorMessage: e.message));
      }
      return;
    } catch (e) {
      _cancelTokens.remove(item.id);
      if (!cancelToken.isCancelled) {
        _update(item.copyWith(status: DownloadStatus.failed, errorMessage: 'Could not read the Instagram post: $e'));
      }
      return;
    }

    if (cancelToken.isCancelled) {
      _cancelTokens.remove(item.id);
      return;
    }
    final dir = await _downloadsDirectory();
    if (cancelToken.isCancelled) {
      _cancelTokens.remove(item.id);
      return;
    }
    final slide = instagramSlideIndex(item.url);
    final jobs = <Future<void>>[];
    for (var i = 0; i < media.length; i++) {
      final m = media[i];
      // One library entry per slide; each keeps a link to just its slide so
      // Retry re-downloads that slide only.
      final number = media.length > 1 ? i + 1 : slide;
      final entry = i == 0
          ? item
          : DownloadItem(
              id: const Uuid().v4(),
              url: '${post.canonicalUrl}?img_index=$number',
              fileName: '',
              filePath: '',
              status: DownloadStatus.resolving,
              createdAt: DateTime.now(),
            );
      final name = number == null ? 'instagram_${post.code}.${m.extension}' : 'instagram_${post.code}_$number.${m.extension}';
      final targetPath = await _uniquePath(dir, name);
      if (cancelToken.isCancelled) {
        _cancelTokens.remove(item.id);
        break;
      }
      jobs.add(
        _download(
          entry.copyWith(mimeType: m.mimeType),
          m.url,
          targetPath,
          headers: const {'User-Agent': instagramDesktopUserAgent, 'Referer': 'https://www.instagram.com/'},
          cancelToken: i == 0 ? cancelToken : null,
        ),
      );
    }
    if (jobs.isEmpty) {
      _cancelTokens.remove(item.id);
      return;
    }
    await Future.wait(jobs);
  }

  /// Downloads [url] into [targetPath] (through a `.part` file, renamed when
  /// complete) over several connections, keeping [item] up to date.
  Future<void> _download(
    DownloadItem item,
    String url,
    String targetPath, {
    Map<String, String> headers = const {},
    CancelToken? cancelToken,
  }) async {
    final id = item.id;
    final token = cancelToken ?? CancelToken();
    if (token.isCancelled) {
      _cancelTokens.remove(id);
      return;
    }
    _cancelTokens[id] = token;
    _activeDownloads.add(id);

    final partPath = '$targetPath.part';
    item = item.copyWith(
      fileName: p.basename(targetPath),
      filePath: targetPath,
      status: DownloadStatus.downloading,
      receivedBytes: 0,
    );
    _update(item);

    try {
      final savedBytes = await _downloader.download(
        url,
        partPath,
        headers: headers,
        cancelToken: token,
        onProgress: (received, total) {
          item = item.copyWith(receivedBytes: received, totalBytes: total > 0 ? total : item.totalBytes);
          _progress(item);
        },
      );
      if (savedBytes == 0) {
        await _deleteIfExists(partPath);
        _update(
          item.copyWith(
            status: DownloadStatus.failed,
            errorMessage: 'The server returned an empty file. This link may not point to a real download.',
          ),
        );
        return;
      }
      await File(partPath).rename(targetPath);
      _update(item.copyWith(status: DownloadStatus.completed, receivedBytes: savedBytes, totalBytes: savedBytes));
    } on DioException catch (e) {
      await _deleteIfExists(partPath);
      final canceled = e.type == DioExceptionType.cancel;
      _update(
        item.copyWith(
          status: canceled ? DownloadStatus.canceled : DownloadStatus.failed,
          errorMessage: canceled ? null : 'Download failed: ${_describe(e)}',
        ),
      );
    } catch (e) {
      await _deleteIfExists(partPath);
      _update(item.copyWith(status: DownloadStatus.failed, errorMessage: 'Download failed: $e'));
    } finally {
      _activeDownloads.remove(id);
      _cancelTokens.remove(id);
      _lastProgressSave.remove(id);
    }
  }

  String _describe(DioException e) {
    final code = e.response?.statusCode;
    if (code == 403 || code == 410) return 'the link expired (HTTP $code). Share it again to retry.';
    if (code != null) return 'HTTP $code';
    switch (e.type) {
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.receiveTimeout:
        return 'the connection timed out.';
      case DioExceptionType.connectionError:
        return 'no connection.';
      default:
        return e.message ?? e.type.name;
    }
  }

  Future<void> _deleteIfExists(String path) async {
    try {
      final f = File(path);
      if (await f.exists()) await f.delete();
    } catch (_) {}
  }

  void cancel(String id) {
    _cancelTokens[id]?.cancel();
    if (_activeDownloads.contains(id)) return;
    final idx = _items.indexWhere((e) => e.id == id);
    if (idx < 0) return;
    final item = _items[idx];
    if (item.status == DownloadStatus.queued ||
        item.status == DownloadStatus.resolving ||
        item.status == DownloadStatus.downloading) {
      _update(item.copyWith(status: DownloadStatus.canceled, errorMessage: null));
    }
  }

  Future<void> retry(String id) async {
    final idx = _items.indexWhere((e) => e.id == id);
    if (idx < 0) return;
    final item = _items[idx];
    await startFromSharedUrl(item.url);
    await remove(id);
  }

  Future<void> remove(String id) async {
    cancel(id);
    final idx = _items.indexWhere((e) => e.id == id);
    if (idx >= 0) {
      final item = _items[idx];
      if (item.filePath.isNotEmpty) {
        if (item.status != DownloadStatus.completed) {
          await _deleteIfExists(item.filePath);
        }
        await _deleteIfExists('${item.filePath}.part');
      }
    }
    _items.removeWhere((e) => e.id == id);
    _emit();
    await DatabaseService.instance.delete(id);
  }

  Future<void> deleteCompletedFile(String id) async {
    final idx = _items.indexWhere((e) => e.id == id);
    if (idx < 0) return;
    final item = _items[idx];
    if (item.filePath.isNotEmpty) {
      await _deleteIfExists(item.filePath);
      await _deleteIfExists('${item.filePath}.part');
    }
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
