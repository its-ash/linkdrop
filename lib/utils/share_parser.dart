/// Pure helpers for turning shared text into a clean URL and for recognising
/// Instagram links. Kept free of Flutter/plugin imports so they are unit-testable.
library;

final RegExp _urlPattern = RegExp(r'https?://[^\s<>"]+', caseSensitive: false);

/// Characters that commonly trail a URL in prose ("see https://x.com/a).")
/// but are never part of it.
final RegExp _trailingJunk = RegExp('[)\\]}>.,;:!?…”’"\']+\$');

/// Extracts the first http(s) URL from arbitrary shared text, stripping
/// trailing punctuation that belongs to the sentence, not the link.
/// When several links are present an Instagram one wins.
String? extractUrl(String sharedText) {
  final matches = _urlPattern
      .allMatches(sharedText.trim())
      .map((m) => m.group(0)!.replaceFirst(_trailingJunk, ''))
      .where((u) => Uri.tryParse(u)?.host.isNotEmpty ?? false)
      .toList();
  if (matches.isEmpty) return null;
  return matches.firstWhere(isInstagramUrl, orElse: () => matches.first);
}

const _instagramHosts = {'instagram.com', 'instagr.am', 'ig.me'};

bool isInstagramUrl(String url) {
  final host = Uri.tryParse(url)?.host.toLowerCase() ?? '';
  return _instagramHosts.any((h) => host == h || host.endsWith('.$h'));
}

/// A resolved Instagram post reference.
class InstagramPost {
  const InstagramPost(this.kind, this.code);

  /// `p`, `reel` or `tv`.
  final String kind;
  final String code;

  String get embedUrl => 'https://www.instagram.com/$kind/$code/embed/captioned/';
  String get canonicalUrl => 'https://www.instagram.com/$kind/$code/';
}

const _kinds = {'p': 'p', 'reel': 'reel', 'reels': 'reel', 'tv': 'tv'};

/// Parses an Instagram post/reel/IGTV link, tolerating `/username/` prefixes,
/// `?igsh=`/`?utm_source=` params, `m.`/`www.` hosts, and the login-wall
/// redirect form `accounts/login/?next=/reel/CODE/`.
/// Returns null for links with no post code (stories, profiles, `/share/...`
/// and short links, which need their redirect followed first).
InstagramPost? parseInstagramPost(String url) {
  final uri = Uri.tryParse(url);
  if (uri == null) return null;
  final fromPath = _fromSegments(uri.pathSegments);
  if (fromPath != null) return fromPath;
  final next = uri.queryParameters['next'];
  if (next != null) {
    final nextUri = Uri.tryParse(next);
    if (nextUri != null) return _fromSegments(nextUri.pathSegments);
  }
  return null;
}

InstagramPost? _fromSegments(List<String> raw) {
  final segments = raw.where((s) => s.isNotEmpty).toList();
  // `/share/reel/<token>` carries a share token, not the post code.
  if (segments.isNotEmpty && segments.first == 'share') return null;
  for (var i = 0; i + 1 < segments.length; i++) {
    final kind = _kinds[segments[i]];
    if (kind != null) {
      final code = segments[i + 1];
      if (RegExp(r'^[A-Za-z0-9_-]+$').hasMatch(code)) return InstagramPost(kind, code);
    }
  }
  return null;
}

/// True when the link needs a redirect followed to learn the post code
/// (instagr.am / ig.me short links, `/share/reel/ID` links).
bool instagramNeedsRedirect(String url) => isInstagramUrl(url) && parseInstagramPost(url) == null;

bool isInstagramStory(String url) => (Uri.tryParse(url)?.pathSegments ?? const <String>[]).contains('stories');

/// Canonical form used for duplicate detection: lower-case host, no
/// tracking params (igsh, utm_*, fbclid...), no fragment, no trailing slash.
/// Instagram post links collapse to `/<kind>/<code>/`.
String normalizeUrl(String url) {
  final post = parseInstagramPost(url);
  if (post != null && isInstagramUrl(url)) return post.canonicalUrl;
  final uri = Uri.tryParse(url);
  if (uri == null) return url;
  final kept = Map<String, List<String>>.fromEntries(
    uri.queryParametersAll.entries.where((e) {
      final k = e.key.toLowerCase();
      return !(k.startsWith('utm_') || k == 'igsh' || k == 'igshid' || k == 'fbclid' || k == 'si');
    }),
  );
  var path = uri.path;
  if (path.length > 1 && path.endsWith('/')) path = path.substring(0, path.length - 1);
  return Uri(
    scheme: uri.scheme.toLowerCase(),
    host: uri.host.toLowerCase(),
    port: uri.hasPort ? uri.port : null,
    path: path,
    queryParameters: kept.isEmpty ? null : kept,
  ).toString();
}
