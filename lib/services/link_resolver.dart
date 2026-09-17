import 'package:dio/dio.dart';

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

final RegExp _urlPattern = RegExp(r'https?://[^\s]+', caseSensitive: false);

/// Extracts the first http(s) URL from arbitrary shared text.
String? extractUrl(String sharedText) =>
    _urlPattern.firstMatch(sharedText.trim())?.group(0);

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

    Response<void>? response;
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
        response = await _dio.getUri<void>(
          uri,
          options: Options(
            followRedirects: true,
            validateStatus: (_) => true,
            headers: {'Range': 'bytes=0-0'},
            responseType: ResponseType.stream,
          ),
        );
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
    final contentLength =
        int.tryParse(headers.value(Headers.contentLengthHeader) ?? '') ?? 0;

    final contentDisposition = headers.value('content-disposition');
    final isAttachment =
        contentDisposition?.toLowerCase().contains('attachment') ?? false;
    if (!isAttachment && (contentType == 'text/html' || contentType == 'application/xhtml+xml')) {
      throw LinkResolveException(
        "This link points to a web page, not a downloadable file. LinkDrop can't pull "
        'videos or posts out of sites like Instagram, YouTube, or Twitter/X — only '
        'direct file links.',
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
        return Uri.decodeComponent(raw.trim());
      }
    }

    final segments = finalUri.pathSegments.where((s) => s.isNotEmpty).toList();
    if (segments.isNotEmpty && segments.last.contains('.')) {
      return Uri.decodeComponent(segments.last);
    }

    final ext = _extensionForMime(contentType);
    final base = segments.isNotEmpty ? segments.last : 'download';
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
