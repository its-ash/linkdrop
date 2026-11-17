import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:dio/dio.dart';

/// Downloads one URL over several HTTP connections at once.
///
/// The file is split into byte ranges that a pool of workers pulls from a
/// shared queue, so a slow connection only holds back its current small piece.
/// Each piece is retried (resuming where it stopped) on network errors. When the
/// server does not support `Range` requests, or the size is unknown, it falls
/// back to a single streamed connection.
class ParallelDownloader {
  ParallelDownloader(
    this._dio, {
    this.maxConnections = 8,
    this.minChunkSize = 256 * 1024,
    this.maxChunkSize = 4 * 1024 * 1024,
    this.maxRetries = 5,
  });

  final Dio _dio;
  final int maxConnections;
  final int minChunkSize;
  final int maxChunkSize;
  final int maxRetries;

  /// Downloads [url] to [savePath] and returns the number of bytes written.
  /// [onProgress] gets (received, total); total is 0 when unknown.
  Future<int> download(
    String url,
    String savePath, {
    Map<String, String> headers = const {},
    CancelToken? cancelToken,
    void Function(int received, int total)? onProgress,
  }) async {
    final probe = await _dio.get<ResponseBody>(
      url,
      cancelToken: cancelToken,
      options: Options(
        responseType: ResponseType.stream,
        followRedirects: true,
        validateStatus: (s) => s != null && s < 400,
        headers: {...headers, 'Range': 'bytes=0-0', 'Accept-Encoding': 'identity'},
      ),
    );
    final total = _totalFromContentRange(probe.headers.value('content-range'));
    if (probe.statusCode == 206 && total != null && total > 0) {
      await _drain(probe.data);
      // Download from the final (redirected) URL so every worker skips redirects.
      final finalUrl = probe.realUri.toString();
      try {
        return await _parallel(finalUrl, savePath, total, headers, cancelToken, onProgress);
      } on _RangeIgnored {
        // Server lied about range support; do it the simple way.
      }
      return _single(url, savePath, headers, cancelToken, onProgress);
    }
    // 200: no range support. Use this response as the single download.
    final length = int.tryParse(probe.headers.value(Headers.contentLengthHeader) ?? '') ?? 0;
    try {
      return await _writeStream(probe.data!.stream, savePath, length, cancelToken, onProgress);
    } on HttpException {
      // Dropped mid-way: start over with retries.
    } on SocketException {
      // Same.
    }
    return _single(url, savePath, headers, cancelToken, onProgress);
  }

  Future<int> _parallel(
    String url,
    String savePath,
    int total,
    Map<String, String> headers,
    CancelToken? cancelToken,
    void Function(int, int)? onProgress,
  ) async {
    final chunkSize = (total / (maxConnections * 3)).ceil().clamp(minChunkSize, maxChunkSize);
    final chunks = <_Chunk>[];
    for (var start = 0; start < total; start += chunkSize) {
      chunks.add(_Chunk(start, min(start + chunkSize, total) - 1));
    }
    final workers = min(maxConnections, chunks.length);

    final file = File(savePath);
    await file.parent.create(recursive: true);
    final raf = await file.open(mode: FileMode.write);
    var received = 0;
    var writeLock = Future<void>.value();

    // RandomAccessFile allows one pending operation at a time: serialize writes.
    Future<void> write(int position, Uint8List bytes) {
      final next = writeLock.then((_) async {
        await raf.setPosition(position);
        await raf.writeFrom(bytes);
      });
      writeLock = next.catchError((_) {});
      return next;
    }

    var nextChunk = 0;
    Object? failure;
    StackTrace? failureStack;
    // One token for all workers: tripped by the caller's token or by the first
    // worker that gives up, so the others stop instead of finishing their chunk.
    final abort = CancelToken();
    unawaited(cancelToken?.whenCancel.then((_) => abort.cancel()));

    Future<void> worker() async {
      while (!abort.isCancelled && nextChunk < chunks.length) {
        final chunk = chunks[nextChunk++];
        var attempt = 0;
        while (true) {
          if (abort.isCancelled) return;
          try {
            await _fetchChunk(url, chunk, headers, abort, (bytes) async {
              await write(chunk.start + chunk.done, bytes);
              chunk.done += bytes.length;
              received += bytes.length;
              onProgress?.call(received, total);
            });
            break;
          } on DioException catch (e) {
            if (e.type == DioExceptionType.cancel) return;
            if (++attempt > maxRetries) rethrow;
          } on HttpException {
            if (++attempt > maxRetries) rethrow;
          } on SocketException {
            if (++attempt > maxRetries) rethrow;
          }
          await Future<void>.delayed(Duration(milliseconds: 400 * attempt * attempt));
        }
      }
    }

    Future<void> guarded() async {
      try {
        await worker();
      } catch (e, st) {
        if (failure == null) {
          failure = e;
          failureStack = st;
        }
        abort.cancel();
      }
    }

    // Wait for every worker so nothing writes after the file is closed.
    await Future.wait(List.generate(workers, (_) => guarded()));
    await writeLock;
    await raf.flush();
    await raf.close();

    if (failure != null) Error.throwWithStackTrace(failure!, failureStack!);
    if (cancelToken?.isCancelled ?? false) {
      throw DioException.requestCancelled(requestOptions: RequestOptions(path: url), reason: 'canceled');
    }

    final written = await file.length();
    if (written != total) {
      throw HttpException('Download incomplete: got $written of $total bytes.');
    }
    return written;
  }

  Future<void> _fetchChunk(
    String url,
    _Chunk chunk,
    Map<String, String> headers,
    CancelToken? cancelToken,
    Future<void> Function(Uint8List bytes) onData,
  ) async {
    final from = chunk.start + chunk.done;
    if (from > chunk.end) return;
    final response = await _dio.get<ResponseBody>(
      url,
      cancelToken: cancelToken,
      options: Options(
        responseType: ResponseType.stream,
        followRedirects: true,
        validateStatus: (s) => s != null && s < 400,
        headers: {...headers, 'Range': 'bytes=$from-${chunk.end}', 'Accept-Encoding': 'identity'},
      ),
    );
    if (response.statusCode != 206) {
      await _drain(response.data);
      throw _RangeIgnored();
    }
    final want = chunk.end - from + 1;
    var got = 0;
    await for (final bytes in response.data!.stream) {
      // Never write past this chunk even if the server sends extra bytes.
      final take = min(bytes.length, want - got);
      if (take <= 0) break;
      await onData(take == bytes.length ? bytes : Uint8List.sublistView(bytes, 0, take));
      got += take;
    }
    if (got < want) throw HttpException('Connection closed early ($got of $want bytes).');
  }

  Future<int> _single(
    String url,
    String savePath,
    Map<String, String> headers,
    CancelToken? cancelToken,
    void Function(int, int)? onProgress,
  ) async {
    var attempt = 0;
    while (true) {
      try {
        final response = await _dio.get<ResponseBody>(
          url,
          cancelToken: cancelToken,
          options: Options(
            responseType: ResponseType.stream,
            followRedirects: true,
            validateStatus: (s) => s != null && s < 400,
            headers: headers,
          ),
        );
        final length = int.tryParse(response.headers.value(Headers.contentLengthHeader) ?? '') ?? 0;
        return await _writeStream(response.data!.stream, savePath, length, cancelToken, onProgress);
      } on DioException catch (e) {
        if (e.type == DioExceptionType.cancel || ++attempt > maxRetries) rethrow;
      } on SocketException {
        if (++attempt > maxRetries) rethrow;
      } on HttpException {
        if (++attempt > maxRetries) rethrow;
      }
      await Future<void>.delayed(Duration(milliseconds: 400 * attempt * attempt));
    }
  }

  Future<int> _writeStream(
    Stream<Uint8List> stream,
    String savePath,
    int total,
    CancelToken? cancelToken,
    void Function(int, int)? onProgress,
  ) async {
    final file = File(savePath);
    await file.parent.create(recursive: true);
    final sink = file.openWrite();
    var received = 0;
    try {
      await for (final bytes in stream) {
        if (cancelToken?.isCancelled ?? false) {
          throw DioException.requestCancelled(requestOptions: RequestOptions(path: savePath), reason: 'canceled');
        }
        sink.add(bytes);
        received += bytes.length;
        onProgress?.call(received, total);
      }
    } finally {
      await sink.flush();
      await sink.close();
    }
    if (total > 0 && received < total) {
      throw HttpException('Download incomplete: got $received of $total bytes.');
    }
    return received;
  }

  Future<void> _drain(ResponseBody? body) async {
    if (body == null) return;
    try {
      await body.stream.listen(null).cancel();
    } catch (_) {}
  }

  static int? _totalFromContentRange(String? value) {
    // "bytes 0-0/918120"
    final m = RegExp(r'/(\d+)\s*$').firstMatch(value ?? '');
    return m == null ? null : int.tryParse(m.group(1)!);
  }
}

class _Chunk {
  _Chunk(this.start, this.end);
  final int start;
  final int end;
  int done = 0;
}

class _RangeIgnored implements Exception {}
