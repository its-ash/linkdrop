import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';

import '../utils/share_parser.dart';

/// Desktop Chrome. Instagram only puts the post data into the page for desktop
/// browsers (and plain HTTP clients); a mobile browser UA gets an empty shell.
const instagramDesktopUserAgent =
    'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 '
    '(KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36';

/// Instagram answers `/share/...` links with an HTML page for browser UAs but
/// with a plain redirect for curl.
const _curlUserAgent = 'curl/8.7.1';

const _webAppId = '936619743392459';

class InstagramExtractException implements Exception {
  InstagramExtractException(this.message);
  final String message;

  @override
  String toString() => message;
}

/// One downloadable file inside a post (a carousel has several).
class InstagramMedia {
  const InstagramMedia({required this.url, required this.isVideo});

  final String url;
  final bool isVideo;

  String get extension => isVideo ? 'mp4' : 'jpg';
  String get mimeType => isVideo ? 'video/mp4' : 'image/jpeg';

  @override
  String toString() => '${isVideo ? 'video' : 'image'} $url';
}

/// Loads a page in a real browser engine and returns its HTML (plus a
/// `<video>` src if one was playing). Used as the last resort; the app plugs in
/// a WebView, tests and tools leave it null.
typedef InstagramBrowserFetch = Future<String?> Function(Uri url, String userAgent);

/// Finds the direct CDN video/image URLs behind a public Instagram post, reel
/// or IGTV link.
///
/// Instagram changes its web app often, so several independent sources are
/// tried in order and the first one that yields media wins:
/// 1. the post page itself (`/p/CODE/`), which embeds the post JSON
///    (`xig_polaris_media`) for logged-out desktop browsers;
/// 2. the logged-out GraphQL post query (`media_id` variables);
/// 3. the older GraphQL shortcode query (`xdt_shortcode_media`);
/// 4. the embed page (`/embed/captioned/`, `contextJSON` / `gql_data`);
/// 5. the post page again with a curl UA (served a different variant);
/// 6. a real WebView ([browserFetch]), if provided.
class InstagramExtractor {
  InstagramExtractor({Dio? dio, this.browserFetch, this.log})
    : _dio =
          dio ??
          Dio(
            BaseOptions(
              connectTimeout: const Duration(seconds: 15),
              receiveTimeout: const Duration(seconds: 20),
            ),
          );

  static final InstagramExtractor instance = InstagramExtractor();

  final Dio _dio;
  InstagramBrowserFetch? browserFetch;

  /// Optional debug sink (the CLI tool prints it).
  void Function(String message)? log;

  /// Works out which post a shared link points at. Handles plain post links
  /// directly and follows redirects for instagr.am / ig.me short links and
  /// `instagram.com/share/reel/ID` links (which the Instagram app shares).
  Future<InstagramPost> resolvePost(String url) async {
    final direct = parseInstagramPost(url);
    if (direct != null) return direct;
    if (isInstagramStory(url)) {
      throw InstagramExtractException("Instagram stories can't be downloaded (they need a login).");
    }
    for (final ua in [_curlUserAgent, instagramDesktopUserAgent]) {
      try {
        final response = await _dio.getUri<String>(
          Uri.parse(url),
          options: Options(
            followRedirects: true,
            maxRedirects: 8,
            validateStatus: (_) => true,
            responseType: ResponseType.plain,
            headers: {'User-Agent': ua, 'Accept': 'text/html,*/*'},
          ),
        );
        final post =
            parseInstagramPost(response.realUri.toString()) ??
            _postFromRedirects(response) ??
            _postFromHtml(response.data ?? '');
        if (post != null) return post;
      } on DioException catch (e) {
        _log('share link ($ua): ${e.type.name}');
      }
    }
    throw InstagramExtractException(
      "Couldn't find a post in this Instagram link. It may be a profile, a story, or private.",
    );
  }

  /// Returns every media file of [post], best quality first per slot.
  Future<List<InstagramMedia>> extractMedia(InstagramPost post) async {
    final session = _Session();
    var sawLoginWall = false;
    var sawPrivate = false;

    Future<List<InstagramMedia>?> attempt(String name, Future<List<InstagramMedia>?> Function() run) async {
      try {
        final media = await run();
        if (media != null && media.isNotEmpty) {
          _log('$name: ${media.length} item(s)');
          return media;
        }
        _log('$name: nothing');
      } on _LoginWall {
        sawLoginWall = true;
        _log('$name: login wall');
      } on _PrivatePost {
        sawPrivate = true;
        _log('$name: private');
      } on DioException catch (e) {
        if (e.type == DioExceptionType.cancel) rethrow;
        _log('$name: ${e.type.name} ${e.response?.statusCode ?? ''}');
      } catch (e) {
        _log('$name: $e');
      }
      return null;
    }

    final sources = <(String, Future<List<InstagramMedia>?> Function())>[
      ('post page', () => _fromPostPage(post, session, instagramDesktopUserAgent)),
      ('graphql media_id', () => _fromGraphqlMediaId(post, session)),
      ('graphql shortcode', () => _fromGraphqlShortcode(post, session)),
      ('embed page', () => _fromEmbed(post)),
      ('post page (curl)', () => _fromPostPage(post, session, _curlUserAgent)),
      if (browserFetch != null) ('webview', () => _fromBrowser(post)),
    ];
    for (final (name, run) in sources) {
      final media = await attempt(name, run);
      if (media != null) return media;
    }

    if (sawPrivate) {
      throw InstagramExtractException('This post is private. Only public posts can be downloaded.');
    }
    if (sawLoginWall) {
      throw InstagramExtractException(
        'Instagram asked for a login (too many requests from this network). '
        'Wait a few minutes or switch between Wi-Fi and mobile data, then retry.',
      );
    }
    throw InstagramExtractException(
      "Couldn't find the video in this post. It may be private, deleted, or age-restricted.",
    );
  }

  // --- sources ---------------------------------------------------------------

  Future<List<InstagramMedia>?> _fromPostPage(InstagramPost post, _Session session, String ua) async {
    final response = await _dio.getUri<String>(
      Uri.parse('https://www.instagram.com/p/${post.code}/'),
      options: Options(
        followRedirects: true,
        validateStatus: (_) => true,
        responseType: ResponseType.plain,
        headers: {
          'User-Agent': ua,
          'Accept': 'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
          'Accept-Language': 'en-US,en;q=0.9',
          'Sec-Fetch-Dest': 'document',
          'Sec-Fetch-Mode': 'navigate',
          'Sec-Fetch-Site': 'none',
          'Sec-Fetch-User': '?1',
          'Upgrade-Insecure-Requests': '1',
          if (session.cookieHeader.isNotEmpty) 'Cookie': session.cookieHeader,
        },
      ),
    );
    session.absorb(response);
    final html = response.data ?? '';
    session.readTokens(html);
    if (_isLoginRedirect(response.realUri)) throw _LoginWall();
    final media = parseInstagramHtml(html, post.code);
    if (media.isEmpty && _looksPrivate(html)) throw _PrivatePost();
    return media;
  }

  /// yt-dlp's logged-out query: `PolarisLoggedOutDesktopWWWPostRootContentQuery`.
  Future<List<InstagramMedia>?> _fromGraphqlMediaId(InstagramPost post, _Session session) async {
    if (session.lsd == null) await _fromPostPage(post, session, instagramDesktopUserAgent).catchError((_) => null);
    final data = await _graphql(
      session,
      post,
      friendlyName: 'PolarisLoggedOutDesktopWWWPostRootContentQuery',
      docId: '27130156389949648',
      variables: {'media_id': shortcodeToMediaId(post.code)},
    );
    return data == null ? null : mediaFromAnyJson(data, post.code);
  }

  /// cobalt's query: `PolarisPostActionLoadPostQueryQuery`.
  Future<List<InstagramMedia>?> _fromGraphqlShortcode(InstagramPost post, _Session session) async {
    final data = await _graphql(
      session,
      post,
      friendlyName: 'PolarisPostActionLoadPostQueryQuery',
      docId: '8845758582119845',
      variables: {
        'shortcode': post.code,
        'fetch_tagged_user_count': null,
        'hoisted_comment_id': null,
        'hoisted_reply_id': null,
      },
      path: 'graphql/query',
    );
    return data == null ? null : mediaFromAnyJson(data, post.code);
  }

  Future<Object?> _graphql(
    _Session session,
    InstagramPost post, {
    required String friendlyName,
    required String docId,
    required Map<String, Object?> variables,
    String path = 'api/graphql',
  }) async {
    final lsd = session.lsd ?? _randomToken(11);
    final response = await _dio.postUri<String>(
      Uri.parse('https://www.instagram.com/$path'),
      data: {
        'av': '0',
        '__d': 'www',
        '__user': '0',
        '__a': '1',
        '__comet_req': '7',
        'lsd': lsd,
        'jazoest': session.jazoest ?? '2${100 + _rand(900)}',
        'fb_api_caller_class': 'RelayModern',
        'fb_api_req_friendly_name': friendlyName,
        'server_timestamps': 'true',
        'variables': jsonEncode(variables),
        'doc_id': docId,
      },
      options: Options(
        validateStatus: (_) => true,
        responseType: ResponseType.plain,
        contentType: Headers.formUrlEncodedContentType,
        headers: {
          'User-Agent': instagramDesktopUserAgent,
          'Accept': '*/*',
          'Accept-Language': 'en-US,en;q=0.9',
          'Origin': 'https://www.instagram.com',
          'Referer': 'https://www.instagram.com/p/${post.code}/',
          'X-IG-App-ID': session.appId ?? _webAppId,
          'X-ASBD-ID': '359341',
          'X-IG-WWW-Claim': '0',
          'X-FB-LSD': lsd,
          'X-FB-Friendly-Name': friendlyName,
          'X-Requested-With': 'XMLHttpRequest',
          'Sec-Fetch-Dest': 'empty',
          'Sec-Fetch-Mode': 'cors',
          'Sec-Fetch-Site': 'same-origin',
          if (session.csrf != null) 'X-CSRFToken': session.csrf,
          if (session.cookieHeader.isNotEmpty) 'Cookie': session.cookieHeader,
        },
      ),
    );
    session.absorb(response);
    final body = (response.data ?? '').replaceFirst(RegExp(r'^for\s*\(;;\);'), '').trim();
    if (body.contains('"require_login":true')) throw _LoginWall();
    if (!body.startsWith('{')) return null;
    final json = jsonDecode(body);
    if (json is Map && json['errors'] != null && json['data'] == null) {
      final errors = jsonEncode(json['errors']);
      _log('graphql errors: ${errors.length > 160 ? errors.substring(0, 160) : errors}');
    }
    return json;
  }

  Future<List<InstagramMedia>?> _fromEmbed(InstagramPost post) async {
    final response = await _dio.getUri<String>(
      Uri.parse('https://www.instagram.com/p/${post.code}/embed/captioned/'),
      options: Options(
        validateStatus: (_) => true,
        responseType: ResponseType.plain,
        headers: {
          'User-Agent': instagramDesktopUserAgent,
          'Accept': 'text/html,application/xhtml+xml,*/*;q=0.8',
          'Accept-Language': 'en-US,en;q=0.9',
          'Sec-Fetch-Dest': 'iframe',
          'Sec-Fetch-Mode': 'navigate',
          'Sec-Fetch-Site': 'cross-site',
          'Referer': 'https://www.google.com/',
        },
      ),
    );
    return parseInstagramHtml(response.data ?? '', post.code);
  }

  Future<List<InstagramMedia>?> _fromBrowser(InstagramPost post) async {
    final html = await browserFetch!(Uri.parse(post.canonicalUrl), instagramDesktopUserAgent);
    if (html == null || html.isEmpty) return null;
    final media = parseInstagramHtml(html, post.code);
    if (media.isNotEmpty) return media;
    // The fetcher may append the playing <video> src as a marker line.
    final src = RegExp(r'<!--linkdrop-video:(https?://[^\s>]+)-->').firstMatch(html)?.group(1);
    if (src != null) return [InstagramMedia(url: src, isVideo: true)];
    return null;
  }

  // --- helpers ---------------------------------------------------------------

  InstagramPost? _postFromRedirects(Response<Object?> response) {
    for (final r in response.redirects.reversed) {
      final post = parseInstagramPost(r.location.toString());
      if (post != null) return post;
    }
    return null;
  }

  InstagramPost? _postFromHtml(String html) {
    for (final pattern in [
      RegExp(r'<meta[^>]+property="og:url"[^>]+content="([^"]+)"'),
      RegExp(r'<link[^>]+rel="canonical"[^>]+href="([^"]+)"'),
      RegExp(r'instagram\.com(?:\\?/[A-Za-z0-9_.]+)?\\?/(?:p|reel|reels|tv)\\?/[A-Za-z0-9_-]+'),
    ]) {
      final m = pattern.firstMatch(html);
      if (m == null) continue;
      var raw = (m.groupCount >= 1 ? m.group(1) : m.group(0))!.replaceAll(r'\/', '/');
      if (!raw.startsWith('http')) raw = 'https://www.$raw/';
      final post = parseInstagramPost(raw);
      if (post != null) return post;
    }
    return null;
  }

  bool _isLoginRedirect(Uri uri) => uri.path.startsWith('/accounts/login') || uri.path.startsWith('/challenge');

  bool _looksPrivate(String html) =>
      html.contains('polaris.privatePostPage') || html.contains('"is_private":true,"is_verified"');

  void _log(String message) => log?.call(message);
}

/// Cookies and page tokens carried between requests of one extraction.
class _Session {
  final Map<String, String> cookies = {};
  String? lsd;
  String? csrf;
  String? appId;
  String? jazoest;

  String get cookieHeader => cookies.entries.map((e) => '${e.key}=${e.value}').join('; ');

  void absorb(Response<Object?> response) {
    for (final raw in response.headers.map['set-cookie'] ?? const <String>[]) {
      final pair = raw.split(';').first;
      final eq = pair.indexOf('=');
      if (eq <= 0) continue;
      final value = pair.substring(eq + 1).trim();
      if (value.isEmpty || value == '""') continue;
      cookies[pair.substring(0, eq).trim()] = value;
    }
    csrf = cookies['csrftoken'] ?? csrf;
  }

  void readTokens(String html) {
    lsd ??= RegExp(r'\["LSD",\[\],\{"token":"([^"]+)"').firstMatch(html)?.group(1);
    final pageCsrf = RegExp(r'"csrf_token":"([^"]+)"').firstMatch(html)?.group(1);
    if (pageCsrf != null) {
      csrf ??= pageCsrf;
      cookies.putIfAbsent('csrftoken', () => pageCsrf);
    }
    appId ??= RegExp(r'"appId":"(\d+)"').firstMatch(html)?.group(1);
    jazoest ??= RegExp(r'jazoest=(\d+)').firstMatch(html)?.group(1);
    final deviceId = RegExp(r'"device_id":"([^"]+)"').firstMatch(html)?.group(1);
    final machineId = RegExp(r'"machine_id":"([^"]+)"').firstMatch(html)?.group(1);
    if (deviceId != null) cookies.putIfAbsent('ig_did', () => deviceId);
    if (machineId != null) cookies.putIfAbsent('mid', () => machineId);
    cookies.putIfAbsent('ig_nrcb', () => '1');
  }
}

class _LoginWall implements Exception {}

class _PrivatePost implements Exception {}

int _seed = DateTime.now().microsecondsSinceEpoch;
int _rand(int max) {
  _seed = (_seed * 1103515245 + 12345) & 0x7fffffff;
  return _seed % max;
}

String _randomToken(int length) {
  const chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789_-';
  return List.generate(length, (_) => chars[_rand(chars.length)]).join();
}

// --- pure parsing (unit-tested) ------------------------------------------------

const _shortcodeAlphabet = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_';

/// Instagram's numeric media id (pk) for a post shortcode.
String shortcodeToMediaId(String shortcode) {
  // Private-post shortcodes carry 28 extra characters after the real code.
  final code = shortcode.length > 28 ? shortcode.substring(0, shortcode.length - 28) : shortcode;
  var id = BigInt.zero;
  final base = BigInt.from(64);
  for (final ch in code.split('')) {
    final digit = _shortcodeAlphabet.indexOf(ch);
    if (digit < 0) throw FormatException('Bad shortcode character: $ch');
    id = id * base + BigInt.from(digit);
  }
  return id.toString();
}

/// Finds the media of post [shortcode] in an Instagram HTML page: JSON script
/// blocks first, then loose regexes for older/odd page variants.
List<InstagramMedia> parseInstagramHtml(String html, String shortcode) {
  if (html.isEmpty) return const [];
  final scripts = RegExp(
    r'<script[^>]*type="application/json"[^>]*>(.*?)</script>',
    dotAll: true,
  ).allMatches(html);
  for (final m in scripts) {
    final text = m.group(1)!;
    if (!text.contains('video_versions') &&
        !text.contains('image_versions2') &&
        !text.contains('video_url') &&
        !text.contains('display_url')) {
      continue;
    }
    try {
      final media = mediaFromAnyJson(jsonDecode(text), shortcode);
      if (media.isNotEmpty) return media;
    } catch (_) {}
  }

  // Embed pages carry the post as an escaped JSON string in `contextJSON`.
  final ctxAt = html.indexOf('"contextJSON":"');
  if (ctxAt >= 0) {
    final literal = readJsonValueAt(html, ctxAt + '"contextJSON":'.length);
    if (literal != null) {
      try {
        final media = mediaFromAnyJson(jsonDecode(jsonDecode(literal) as String), shortcode);
        if (media.isNotEmpty) return media;
      } catch (_) {}
    }
  }

  // Any JSON object literal that holds the media keys.
  for (final key in ['"video_versions":', '"carousel_media":', '"video_url":']) {
    var at = html.indexOf(key);
    while (at >= 0) {
      final value = readJsonValueAt(html, at + key.length);
      if (value != null) {
        try {
          final decoded = jsonDecode(value);
          final media = key == '"video_versions":'
              ? _bestVideo(decoded)
              : key == '"carousel_media":'
              ? _fromCarousel(decoded)
              : (decoded is String && decoded.startsWith('http') ? [InstagramMedia(url: decoded, isVideo: true)] : null);
          if (media != null && media.isNotEmpty) return media;
        } catch (_) {}
      }
      at = html.indexOf(key, at + key.length);
    }
  }

  final ogVideo = RegExp(
    r'<meta[^>]+property="og:video(?::secure_url)?"[^>]+content="([^"]+)"',
  ).firstMatch(html)?.group(1);
  if (ogVideo != null) return [InstagramMedia(url: _unescapeHtml(ogVideo), isVideo: true)];
  return const [];
}

/// Walks any decoded JSON for the media object of [shortcode] in either API
/// shape: the new one (`video_versions`, `image_versions2`, `carousel_media`)
/// or the old GraphQL one (`video_url`, `display_url`, `edge_sidecar_to_children`).
List<InstagramMedia> mediaFromAnyJson(Object? json, String shortcode) {
  Map<String, Object?>? best;
  var bestScore = 0;

  void consider(Map<String, Object?> node) {
    final hasMedia =
        node.containsKey('video_versions') ||
        node.containsKey('carousel_media') ||
        node.containsKey('image_versions2') ||
        node.containsKey('video_url') ||
        node.containsKey('edge_sidecar_to_children') ||
        node.containsKey('display_url');
    if (!hasMedia) return;
    final code = node['code'] ?? node['shortcode'];
    var score = 1;
    if (code == shortcode) score += 10;
    if (node['video_versions'] is List || node['video_url'] is String) score += 2;
    if (node['carousel_media'] is List || node['edge_sidecar_to_children'] is Map) score += 3;
    if (score > bestScore) {
      bestScore = score;
      best = node;
    }
  }

  void walk(Object? o, int depth) {
    if (depth > 60) return;
    if (o is Map) {
      final map = o.cast<String, Object?>();
      // Preferred, well-known containers.
      final polaris = map['xig_polaris_media'];
      if (polaris is Map && polaris['if_not_gated_logged_out'] is Map) {
        consider((polaris['if_not_gated_logged_out'] as Map).cast<String, Object?>());
      }
      for (final key in ['xdt_shortcode_media', 'shortcode_media']) {
        if (map[key] is Map) consider((map[key] as Map).cast<String, Object?>());
      }
      consider(map);
      for (final v in map.values) {
        walk(v, depth + 1);
      }
    } else if (o is List) {
      for (final v in o) {
        walk(v, depth + 1);
      }
    }
  }

  walk(json, 0);
  final node = best;
  if (node == null) return const [];
  return mediaFromNode(node);
}

/// Media of one post node, in either API shape.
List<InstagramMedia> mediaFromNode(Map<String, Object?> node) {
  final carousel = _fromCarousel(node['carousel_media']);
  if (carousel != null && carousel.isNotEmpty) return carousel;

  final sidecar = node['edge_sidecar_to_children'];
  if (sidecar is Map && sidecar['edges'] is List) {
    final items = <InstagramMedia>[];
    for (final edge in sidecar['edges'] as List) {
      final child = edge is Map ? edge['node'] : null;
      if (child is Map) items.addAll(mediaFromNode(child.cast<String, Object?>()));
    }
    if (items.isNotEmpty) return items;
  }

  final video = _bestVideo(node['video_versions']);
  if (video != null) return video;
  final videoUrl = node['video_url'];
  if (videoUrl is String && videoUrl.startsWith('http')) return [InstagramMedia(url: videoUrl, isVideo: true)];

  final image = _bestImage(node['image_versions2']);
  if (image != null) return [image];
  final displayUrl = node['display_url'];
  if (displayUrl is String && displayUrl.startsWith('http')) return [InstagramMedia(url: displayUrl, isVideo: false)];
  return const [];
}

List<InstagramMedia>? _fromCarousel(Object? carousel) {
  if (carousel is! List) return null;
  final items = <InstagramMedia>[];
  for (final child in carousel) {
    if (child is Map) {
      final media = mediaFromNode(child.cast<String, Object?>());
      if (media.isNotEmpty) items.add(media.first);
    }
  }
  return items;
}

/// The largest progressive MP4 (with audio) from a `video_versions` list.
List<InstagramMedia>? _bestVideo(Object? versions) {
  if (versions is! List || versions.isEmpty) return null;
  Map? best;
  var bestPixels = -1;
  for (final v in versions) {
    if (v is! Map || v['url'] is! String) continue;
    final pixels = ((v['width'] as num?) ?? 0) * ((v['height'] as num?) ?? 0);
    // Ties keep the first entry, which Instagram lists as the best one.
    if (pixels > bestPixels) {
      bestPixels = pixels.toInt();
      best = v;
    }
  }
  if (best == null) return null;
  return [InstagramMedia(url: best['url'] as String, isVideo: true)];
}

InstagramMedia? _bestImage(Object? imageVersions) {
  final candidates = imageVersions is Map ? imageVersions['candidates'] : null;
  if (candidates is! List || candidates.isEmpty) return null;
  Map? best;
  var bestPixels = -1;
  for (final c in candidates) {
    if (c is! Map || c['url'] is! String) continue;
    final pixels = (((c['width'] as num?) ?? 0) * ((c['height'] as num?) ?? 0)).toInt();
    if (pixels > bestPixels) {
      bestPixels = pixels;
      best = c;
    }
  }
  return best == null ? null : InstagramMedia(url: best['url'] as String, isVideo: false);
}

/// Returns the raw JSON text of the value (object, array, string, number,
/// literal) that starts at or after [start] in [s], or null.
String? readJsonValueAt(String s, int start) {
  var i = start;
  while (i < s.length && (s[i] == ' ' || s[i] == '\n' || s[i] == '\t' || s[i] == '\r')) {
    i++;
  }
  if (i >= s.length) return null;
  final first = s[i];
  if (first == '"') {
    var j = i + 1;
    while (j < s.length) {
      final c = s[j];
      if (c == r'\') {
        j += 2;
        continue;
      }
      if (c == '"') return s.substring(i, j + 1);
      j++;
    }
    return null;
  }
  if (first == '{' || first == '[') {
    var depth = 0;
    var inString = false;
    for (var j = i; j < s.length; j++) {
      final c = s[j];
      if (inString) {
        if (c == r'\') {
          j++;
        } else if (c == '"') {
          inString = false;
        }
        continue;
      }
      if (c == '"') {
        inString = true;
      } else if (c == '{' || c == '[') {
        depth++;
      } else if (c == '}' || c == ']') {
        depth--;
        if (depth == 0) return s.substring(i, j + 1);
      }
    }
    return null;
  }
  final end = RegExp(r'[,}\]]').firstMatch(s.substring(i))?.start;
  return end == null ? null : s.substring(i, i + end).trim();
}

String _unescapeHtml(String s) =>
    s.replaceAll('&amp;', '&').replaceAll('&quot;', '"').replaceAll('&#039;', "'").replaceAll('&lt;', '<').replaceAll('&gt;', '>');
