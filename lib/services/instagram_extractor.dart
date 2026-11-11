import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../utils/share_parser.dart';

const _browserUserAgent =
    'Mozilla/5.0 (Linux; Android 13; Pixel 7) AppleWebKit/537.36 '
    '(KHTML, like Gecko) Chrome/120.0.0.0 Mobile Safari/537.36';

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

  /// Works out which post a shared link points at. Handles plain post links
  /// directly and follows redirects for instagr.am / ig.me short links and
  /// `instagram.com/share/reel/ID` links (which the Instagram app shares).
  Future<InstagramPost> resolvePost(String url, {Dio? dio}) async {
    final direct = parseInstagramPost(url);
    if (direct != null) return direct;
    if (isInstagramStory(url)) {
      throw InstagramExtractException('Instagram stories can\'t be downloaded (they need a login).');
    }
    final client = dio ??
        Dio(BaseOptions(
          connectTimeout: const Duration(seconds: 10),
          receiveTimeout: const Duration(seconds: 10),
          headers: {'User-Agent': _browserUserAgent},
        ));
    try {
      final response = await client.getUri<void>(
        Uri.parse(url),
        options: Options(
          followRedirects: true,
          maxRedirects: 8,
          validateStatus: (_) => true,
          responseType: ResponseType.stream,
          headers: {'User-Agent': _browserUserAgent},
        ),
      );
      final finalUrl = response.realUri.toString();
      final post = parseInstagramPost(finalUrl);
      if (post != null) return post;
    } on DioException catch (e) {
      throw InstagramExtractException('Could not open the Instagram link (${e.type.name}).');
    }
    throw InstagramExtractException(
      "Couldn't find a post in this Instagram link. It may be a profile, a story, or private.",
    );
  }

  /// Resolves [postUrl] to a direct media URL, retrying once on a transient
  /// WebView failure (Instagram is flaky about the first load).
  Future<String> extractMediaUrl(String postUrl) async {
    final post = await resolvePost(postUrl);
    try {
      return await _renderAndExtract(post);
    } on InstagramExtractException {
      return _renderAndExtract(post);
    }
  }

  /// Renders the post's embed page in a hidden WebView and resolves to the
  /// direct media URL once found, or throws [InstagramExtractException] if the
  /// post isn't public, doesn't exist, or no media could be located in time.
  Future<String> _renderAndExtract(InstagramPost post) async {
    final embedUrl = post.embedUrl;
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
      ..setUserAgent(_browserUserAgent)
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
                // Only fall back to the still image once the video had a fair
                // chance to render, otherwise a reel saves as its thumbnail.
                final raw = await controller.runJavaScriptReturningResult(
                  attempts >= 8 ? _extractScriptWithImage : _extractScript,
                );
                final decoded = _decodeJsResult(raw);
                if (decoded != null && decoded.isNotEmpty && !decoded.startsWith('blob:')) {
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
  return null;
})();
''';

  static const _extractScriptWithImage = r'''
(function() {
  var video = document.querySelector('video');
  if (video && video.src) { return video.src; }
  var source = document.querySelector('video source');
  if (source && source.src) { return source.src; }
  var meta = document.querySelector('meta[property="og:video"]') ||
             document.querySelector('meta[property="og:video:secure_url"]');
  if (meta && meta.content) { return meta.content; }
  var img = document.querySelector('.EmbeddedMediaImage') ||
            document.querySelector('meta[property="og:image"]');
  if (img && (img.src || img.content)) { return img.src || img.content; }
  return null;
})();
''';
}
