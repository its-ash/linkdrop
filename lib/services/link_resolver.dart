import 'package:dio/dio.dart';
import 'package:path/path.dart' as p;

export '../utils/share_parser.dart' show extractUrl;

class ResolvedLink {
  const ResolvedLink({
    required this.url,
    required this.fileName,
    required this.mimeType,
    required this.totalBytes,
  });

  final String url;
  final String fileName;
  final String? mimeType;
  final int totalBytes;
}

class LinkResolveException implements Exception {
  LinkResolveException(this.message);
  final String message;

  @override
  String toString() => message;
}


class LinkResolver {
  LinkResolver(this._dio);

  final Dio _dio;

  /// Probes a URL via HEAD (falling back to a ranged GET) to confirm it is
  /// reachable and resolve its final redirected location, file name, mime
  /// type, and content length before a real download starts.
  Future<ResolvedLink> resolve(String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null ||
        !uri.isAbsolute ||
        !(uri.scheme == 'http' || uri.scheme == 'https')) {
      throw LinkResolveException('Not a valid downloadable link.');
    }

    Response<dynamic>? response;
    try {
      response = await _dio.headUri<void>(
        uri,
        options: Options(followRedirects: true, validateStatus: (_) => true),
      );
    } on DioException catch (e) {
      throw LinkResolveException(_describeDioError(e));
    }

    if (response.statusCode == null || response.statusCode! >= 400) {
      // Some servers reject HEAD; retry with a byte-ranged GET.
      try {
        final ranged = await _dio.getUri<ResponseBody>(
          uri,
          options: Options(
            followRedirects: true,
            validateStatus: (_) => true,
            headers: {'Range': 'bytes=0-0'},
            responseType: ResponseType.stream,
          ),
        );
        try {
          await ranged.data?.stream.listen(null).cancel();
        } catch (_) {}
        response = ranged;
      } on DioException catch (e) {
        throw LinkResolveException(_describeDioError(e));
      }
    }

    if (response.statusCode == null || response.statusCode! >= 400) {
      throw LinkResolveException(
        'Resource is not accessible (HTTP ${response.statusCode ?? 'error'}).',
      );
    }

    final headers = response.headers;
    final finalUri = response.realUri;
    final contentType = headers
        .value(Headers.contentTypeHeader)
        ?.split(';')
        .first
        .trim();
    final contentLength = response.statusCode == 206
        ? _totalFromContentRange(headers.value('content-range')) ?? 0
        : int.tryParse(headers.value(Headers.contentLengthHeader) ?? '') ?? 0;

    final contentDisposition = headers.value('content-disposition');
    final isAttachment =
        contentDisposition?.toLowerCase().contains('attachment') ?? false;
    if (!isAttachment && (contentType == 'text/html' || contentType == 'application/xhtml+xml')) {
      throw LinkResolveException(
        "This link points to a web page, not a downloadable file. LinkDrop can't pull "
        'videos out of sites like YouTube or Twitter/X — only Instagram posts/reels '
        'and direct file links.',
      );
    }

    final fileName = _resolveFileName(
      contentDisposition,
      finalUri,
      contentType,
    );

    return ResolvedLink(
      url: finalUri.toString(),
      fileName: fileName,
      mimeType: contentType,
      totalBytes: contentLength,
    );
  }

  String _describeDioError(DioException e) {
    switch (e.type) {
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.receiveTimeout:
      case DioExceptionType.sendTimeout:
        return 'Connection to the resource timed out.';
      case DioExceptionType.connectionError:
        return 'Could not connect to the resource.';
      default:
        return 'Failed to resolve the link.';
    }
  }

  int? _totalFromContentRange(String? value) {
    final m = RegExp(r'/(\d+)\s*$').firstMatch(value ?? '');
    return m == null ? null : int.tryParse(m.group(1)!);
  }

  String _sanitizeFileName(String raw) {
    var name = p.basename(raw.replaceAll('\\', '/')).trim();
    name = name.replaceAll(RegExp(r'[\x00/\\]+'), '').replaceAll('..', '').trim();
    if (name.isEmpty || name == '.') return '';
    return name;
  }

  String _resolveFileName(
    String? contentDisposition,
    Uri finalUri,
    String? contentType,
  ) {
    if (contentDisposition != null) {
      final starMatch = RegExp(
        '''filename\\*=(?:UTF-8'')?"?([^;"]+)"?''',
        caseSensitive: false,
      ).firstMatch(contentDisposition);
      final plainMatch = RegExp(
        'filename="?([^;"]+)"?',
        caseSensitive: false,
      ).firstMatch(contentDisposition);
      final raw = starMatch?.group(1) ?? plainMatch?.group(1);
      if (raw != null && raw.trim().isNotEmpty) {
        final trimmed = raw.trim();
        String decoded;
        try {
          decoded = Uri.decodeComponent(trimmed);
        } catch (_) {
          decoded = trimmed;
        }
        final safe = _sanitizeFileName(decoded);
        if (safe.isNotEmpty) return safe;
      }
    }

    final segments = finalUri.pathSegments.where((s) => s.isNotEmpty).toList();
    if (segments.isNotEmpty && segments.last.contains('.')) {
      final safe = _sanitizeFileName(segments.last);
      if (safe.isNotEmpty) return safe;
    }

    final ext = _extensionForMime(contentType);
    final rawBase = segments.isNotEmpty ? _sanitizeFileName(segments.last) : '';
    final base = rawBase.isNotEmpty ? rawBase : 'download';
    return '$base${ext.isNotEmpty ? '.$ext' : ''}';
  }

  String _extensionForMime(String? mimeType) {
    switch (mimeType) {
      case 'image/jpeg':
        return 'jpg';
      case 'image/png':
        return 'png';
      case 'image/gif':
        return 'gif';
      case 'image/webp':
        return 'webp';
      case 'video/mp4':
        return 'mp4';
      case 'audio/mpeg':
        return 'mp3';
      case 'application/pdf':
        return 'pdf';
      case 'application/zip':
        return 'zip';
      case 'text/plain':
        return 'txt';
      case 'application/json':
        return 'json';
      default:
        return '';
    }
  }
}
