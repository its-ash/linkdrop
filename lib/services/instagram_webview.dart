import 'dart:async';
import 'dart:convert';

import 'package:webview_flutter/webview_flutter.dart';

/// Last-resort page loader for [InstagramExtractor.browserFetch]: renders the
/// post in a hidden WebView (a real browser engine, so it passes checks a
/// plain HTTP client may not) and returns the page HTML. If a `<video>` is
/// playing with a real (non-blob) src, that src is appended as a marker
/// comment the extractor understands.
Future<String?> fetchWithWebView(Uri url, String userAgent) async {
  final completer = Completer<String?>();
  late final WebViewController controller;
  Timer? poll;
  Timer? timeout;
  var attempts = 0;

  void finish(String? html) {
    if (!completer.isCompleted) completer.complete(html);
    poll?.cancel();
    timeout?.cancel();
  }

  Future<String?> snapshot() async {
    final raw = await controller.runJavaScriptReturningResult(_snapshotScript);
    var text = raw.toString();
    try {
      final decoded = jsonDecode(text);
      if (decoded is String) text = decoded;
    } catch (_) {}
    return text == 'null' || text.isEmpty ? null : text;
  }

  controller = WebViewController()
    ..setJavaScriptMode(JavaScriptMode.unrestricted)
    ..setUserAgent(userAgent)
    ..setNavigationDelegate(
      NavigationDelegate(
        onPageFinished: (_) {
          poll?.cancel();
          poll = Timer.periodic(const Duration(milliseconds: 700), (_) async {
            attempts++;
            try {
              final html = await snapshot();
              if (html == null) return;
              final ready =
                  html.contains('<!--linkdrop-video:') ||
                  html.contains('"video_versions"') ||
                  html.contains('"video_url"');
              // Give the page a few polls to hydrate; then take what we have.
              if (ready || attempts >= 12) finish(html);
            } catch (_) {}
          });
        },
        onWebResourceError: (error) {
          if (error.isForMainFrame ?? false) finish(null);
        },
      ),
    )
    ..loadRequest(url);

  timeout = Timer(const Duration(seconds: 20), () async {
    try {
      finish(await snapshot());
    } catch (_) {
      finish(null);
    }
  });

  try {
    return await completer.future;
  } finally {
    unawaited(controller.loadRequest(Uri.parse('about:blank')).catchError((_) {}));
    unawaited(controller.clearCache().catchError((_) {}));
  }
}

const _snapshotScript = r'''
(function() {
  var html = document.documentElement ? document.documentElement.outerHTML : '';
  var v = document.querySelector('video');
  var src = v && (v.currentSrc || v.src);
  if (!src) { var s = document.querySelector('video source'); src = s && s.src; }
  if (src && src.indexOf('blob:') !== 0) { html += '<!--linkdrop-video:' + src + '-->'; }
  return html;
})();
''';
