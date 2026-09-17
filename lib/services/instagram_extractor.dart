import 'dart:async';
import 'dart:convert';

import 'package:webview_flutter/webview_flutter.dart';

class InstagramExtractException implements Exception {
  InstagramExtractException(this.message);
  final String message;

  @override
  String toString() => message;
}

/// Extracts the direct CDN video/image URL behind a public Instagram post,
/// reel, or IGTV link.
///
/// Instagram serves its content client-side via JavaScript and blocks plain
/// HTTP requests with a login wall, so a real (headless) `WebView` renders
/// the page like a browser would, then JS pulls the `<video>`/`<img>`
/// `src` out of the rendered DOM once the page settles.
class InstagramExtractor {
  InstagramExtractor._();

  static final InstagramExtractor instance = InstagramExtractor._();

  static bool isInstagramUrl(String url) {
    final host = Uri.tryParse(url)?.host.toLowerCase() ?? '';
    return host == 'instagram.com' || host.endsWith('.instagram.com');
  }

  /// Renders [postUrl] in a hidden WebView and resolves to the direct media
  /// URL once found, or throws [InstagramExtractException] if the post
  /// isn't public, doesn't exist, or no media could be located in time.
  Future<String> extractMediaUrl(String postUrl) async {
    final embedUrl = _toEmbedUrl(postUrl);
    final completer = Completer<String>();
    late final WebViewController controller;
    Timer? timeoutTimer;
    Timer? pollTimer;

    void finishError(String message) {
      if (!completer.isCompleted) {
        completer.completeError(InstagramExtractException(message));
      }
      timeoutTimer?.cancel();
      pollTimer?.cancel();
    }

    void finishSuccess(String url) {
      if (!completer.isCompleted) {
        completer.complete(url);
      }
      timeoutTimer?.cancel();
      pollTimer?.cancel();
    }

    controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setUserAgent(
        'Mozilla/5.0 (Linux; Android 13; Pixel 7) AppleWebKit/537.36 '
        '(KHTML, like Gecko) Chrome/120.0.0.0 Mobile Safari/537.36',
      )
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageFinished: (_) {
            pollTimer?.cancel();
            var attempts = 0;
            pollTimer = Timer.periodic(const Duration(milliseconds: 500), (timer) async {
              attempts++;
              if (completer.isCompleted) {
                timer.cancel();
                return;
              }
              if (attempts > 20) {
                timer.cancel();
                finishError(
                  "Couldn't find a video on this post. It may be private, "
                  "deleted, or a carousel post that isn't supported yet.",
                );
                return;
              }
              try {
                final raw = await controller.runJavaScriptReturningResult(_extractScript);
                final decoded = _decodeJsResult(raw);
                if (decoded != null && decoded.isNotEmpty) {
                  timer.cancel();
                  finishSuccess(decoded);
                }
              } catch (_) {
                // page may still be settling; keep polling until timeout
              }
            });
          },
          onWebResourceError: (error) {
            if (error.isForMainFrame ?? true) {
              finishError('Could not load the Instagram post (${error.description}).');
            }
          },
        ),
      )
      ..loadRequest(Uri.parse(embedUrl));

    timeoutTimer = Timer(const Duration(seconds: 15), () {
      finishError('Timed out trying to resolve this Instagram post.');
    });

    try {
      return await completer.future;
    } finally {
      unawaited(controller.clearCache());
    }
  }

  String _toEmbedUrl(String postUrl) {
    final uri = Uri.parse(postUrl);
    final segments = uri.pathSegments.where((s) => s.isNotEmpty).toList();
    // Strip a leading username segment for profile-style URLs (/user/reel/CODE/).
    final kindIndex = segments.indexWhere((s) => s == 'p' || s == 'reel' || s == 'tv');
    if (kindIndex == -1 || kindIndex + 1 >= segments.length) {
      throw InstagramExtractException('Not a recognizable Instagram post link.');
    }
    final kind = segments[kindIndex];
    final code = segments[kindIndex + 1];
    return 'https://www.instagram.com/$kind/$code/embed/captioned/';
  }

  String? _decodeJsResult(Object? raw) {
    if (raw == null) return null;
    var text = raw.toString();
    if (text == 'null' || text.isEmpty) return null;
    // runJavaScriptReturningResult returns a JSON-encoded string on Android.
    try {
      final decoded = jsonDecode(text);
      if (decoded is String && decoded.isNotEmpty) return decoded;
    } catch (_) {
      // fall through to raw string handling below
    }
    if (text.length >= 2 && text.startsWith('"') && text.endsWith('"')) {
      text = text.substring(1, text.length - 1);
    }
    return text.isEmpty ? null : text;
  }

  static const _extractScript = r'''
(function() {
  var video = document.querySelector('video');
  if (video && video.src) { return video.src; }
  var source = document.querySelector('video source');
  if (source && source.src) { return source.src; }
  var meta = document.querySelector('meta[property="og:video"]') ||
             document.querySelector('meta[property="og:video:secure_url"]');
  if (meta && meta.content) { return meta.content; }
  var img = document.querySelector('meta[property="og:image"]');
  if (img && img.content) { return img.content; }
  return null;
})();
''';
}
