import 'dart:io';
import 'dart:typed_data';

import 'package:file_selector/file_selector.dart';

class PngExportService {
  const PngExportService();

  Future<String?> export(
    Uint8List bytes, {
    DateTime? now,
    String songTitle = '',
    String imageType = '',
  }) async {
    final filename = suggestedPngFilename(
      now ?? DateTime.now(),
      songTitle: songTitle,
      imageType: imageType,
    );
    final location = await getSaveLocation(
      suggestedName: filename,
      acceptedTypeGroups: const [
        XTypeGroup(label: 'PNG 图片', extensions: ['png']),
      ],
    );
    if (location == null) {
      return null;
    }
    await File(location.path).writeAsBytes(bytes, flush: true);
    return location.path;
  }
}

String suggestedPngFilename(
  DateTime time, {
  String songTitle = '',
  String imageType = '',
}) {
  String twoDigits(int value) => value.toString().padLeft(2, '0');
  final timestamp =
      '${time.year}${twoDigits(time.month)}${twoDigits(time.day)}-'
      '${twoDigits(time.hour)}${twoDigits(time.minute)}${twoDigits(time.second)}';
  final safeTitle = _safeFilenamePart(songTitle);
  final safeType = _safeFilenamePart(imageType);
  if (safeTitle.isEmpty || safeType.isEmpty) {
    return 'jianpu-keyboard-$timestamp.png';
  }
  return '$safeTitle-$safeType-$timestamp.png';
}

String _safeFilenamePart(String value) => value
    .trim()
    .replaceAll(RegExp(r'[<>:"：/\\|?*\x00-\x1F]'), ' ')
    .replaceAll(RegExp(r'\s+'), ' ')
    .trim()
    .replaceAll(' ', '-');
