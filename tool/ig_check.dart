// Live check of the Instagram extractor and the parallel downloader.
//
//   dart run tool/ig_check.dart <instagram url> [more urls...]
//   dart run tool/ig_check.dart --download <dir> <instagram url>
//
// Pure Dart (no Flutter), so it runs on the Mac against real Instagram.
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:linkdrop/services/instagram_extractor.dart';
import 'package:linkdrop/services/parallel_downloader.dart';

Future<void> main(List<String> args) async {
  String? downloadDir;
  final urls = <String>[];
  for (var i = 0; i < args.length; i++) {
    if (args[i] == '--download') {
      downloadDir = args[++i];
    } else {
      urls.add(args[i]);
    }
  }
  if (urls.isEmpty) {
    stderr.writeln('usage: dart run tool/ig_check.dart [--download <dir>] <url>...');
    exit(64);
  }

  final extractor = InstagramExtractor(log: (m) => stdout.writeln('    · $m'));
  var failures = 0;
  for (final url in urls) {
    stdout.writeln(url);
    try {
      final post = await extractor.resolvePost(url);
      stdout.writeln('  post ${post.kind}/${post.code} (media id ${shortcodeToMediaId(post.code)})');
      final media = await extractor.extractMedia(post);
      for (final m in media) {
        stdout.writeln('  ${m.isVideo ? 'VIDEO' : 'IMAGE'} ${m.url.substring(0, m.url.length.clamp(0, 110))}');
      }
      if (downloadDir != null) {
        final dio = Dio();
        final downloader = ParallelDownloader(dio);
        for (var i = 0; i < media.length; i++) {
          final path = '$downloadDir/${post.code}_${i + 1}.${media[i].extension}';
          final watch = Stopwatch()..start();
          final bytes = await downloader.download(
            media[i].url,
            path,
            headers: {'User-Agent': instagramDesktopUserAgent},
          );
          stdout.writeln('  saved $path: $bytes bytes in ${watch.elapsedMilliseconds} ms');
        }
      }
    } catch (e) {
      failures++;
      stdout.writeln('  FAILED: $e');
    }
  }
  exit(failures == 0 ? 0 : 1);
}
