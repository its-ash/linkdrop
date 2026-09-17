import 'package:flutter/material.dart';

enum FileKind { image, video, audio, pdf, archive, document, generic }

FileKind fileKindFor(String? mimeType, String fileName) {
  final mime = mimeType ?? '';
  final ext = fileName.contains('.') ? fileName.split('.').last.toLowerCase() : '';

  if (mime.startsWith('image/') || ['jpg', 'jpeg', 'png', 'gif', 'webp', 'heic'].contains(ext)) {
    return FileKind.image;
  }
  if (mime.startsWith('video/') || ['mp4', 'mov', 'mkv', 'webm', 'avi'].contains(ext)) {
    return FileKind.video;
  }
  if (mime.startsWith('audio/') || ['mp3', 'wav', 'm4a', 'flac', 'ogg'].contains(ext)) {
    return FileKind.audio;
  }
  if (mime.contains('pdf') || ext == 'pdf') return FileKind.pdf;
  if (mime.contains('zip') || mime.contains('compressed') || ['zip', 'rar', '7z', 'tar', 'gz'].contains(ext)) {
    return FileKind.archive;
  }
  if (mime.contains('word') ||
      mime.contains('document') ||
      mime.contains('text') ||
      ['doc', 'docx', 'txt', 'rtf', 'odt'].contains(ext)) {
    return FileKind.document;
  }
  return FileKind.generic;
}

class FileKindStyle {
  const FileKindStyle({required this.icon, required this.color});

  final IconData icon;
  final Color color;

  static FileKindStyle of(FileKind kind) => switch (kind) {
    FileKind.image => const FileKindStyle(icon: Icons.image_rounded, color: Color(0xFF0D9488)),
    FileKind.video => const FileKindStyle(icon: Icons.movie_rounded, color: Color(0xFF7C3AED)),
    FileKind.audio => const FileKindStyle(icon: Icons.graphic_eq_rounded, color: Color(0xFFEA580C)),
    FileKind.pdf => const FileKindStyle(icon: Icons.picture_as_pdf_rounded, color: Color(0xFFDC2626)),
    FileKind.archive => const FileKindStyle(icon: Icons.folder_zip_rounded, color: Color(0xFFCA8A04)),
    FileKind.document => const FileKindStyle(icon: Icons.description_rounded, color: Color(0xFF2563EB)),
    FileKind.generic => const FileKindStyle(icon: Icons.insert_drive_file_rounded, color: Color(0xFF6B7280)),
  };
}
