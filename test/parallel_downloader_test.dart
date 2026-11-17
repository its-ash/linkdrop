import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:linkdrop/services/parallel_downloader.dart';

/// Local server serving [body]; optionally ignores Range and/or cuts the
/// first N ranged responses short to exercise retries.
class _Server {
  _Server(this.body, {this.ranges = true, this.dropFirst = 0});

  final Uint8List body;
  final bool ranges;
  int dropFirst;
  late HttpServer server;
  int rangedRequests = 0;

  String get url => 'http://127.0.0.1:${server.port}/file.mp4';

  Future<void> start() async {
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((req) async {
      final res = req.response;
      final range = req.headers.value('range');
      final m = range == null ? null : RegExp(r'bytes=(\d+)-(\d*)').firstMatch(range);
      if (!ranges || m == null) {
        res.contentLength = body.length;
        res.add(body);
        await res.close();
        return;
      }
      rangedRequests++;
      final start = int.parse(m.group(1)!);
      final end = m.group(2)!.isEmpty ? body.length - 1 : int.parse(m.group(2)!);
      res.statusCode = 206;
      res.headers.set('content-range', 'bytes $start-$end/${body.length}');
      final slice = body.sublist(start, end + 1);
      res.contentLength = slice.length;
      if (slice.length > 1000 && dropFirst > 0) {
        dropFirst--;
        final socket = await res.detachSocket();
        socket.add(slice.sublist(0, slice.length ~/ 2));
        await socket.flush();
        await socket.close();
        return;
      }
      res.add(slice);
      await res.close();
    });
  }
}

void main() {
  final body = Uint8List.fromList(List.generate(3 * 1024 * 1024 + 123, (i) => (i * 31 + 7) & 0xff));
  late Directory dir;

  setUp(() async => dir = await Directory.systemTemp.createTemp('pd'));
  tearDown(() async => dir.delete(recursive: true));

  Future<void> run(_Server s, {int connections = 8}) async {
    await s.start();
    final out = '${dir.path}/out.mp4';
    var last = 0;
    final n = await ParallelDownloader(
      Dio(),
      maxConnections: connections,
      minChunkSize: 64 * 1024,
    ).download(s.url, out, onProgress: (r, t) => last = r);
    await s.server.close(force: true);
    expect(n, body.length);
    expect(last, body.length);
    expect(await File(out).readAsBytes(), body);
  }

  test('splits into ranges and reassembles the exact bytes', () async {
    final s = _Server(body);
    await run(s);
    expect(s.rangedRequests, greaterThan(8));
  });

  test('resumes chunks after connections drop mid-way', () async {
    await run(_Server(body, dropFirst: 5));
  });

  test('falls back to one connection when Range is ignored', () async {
    await run(_Server(body, ranges: false));
  });
}
