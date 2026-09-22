import 'dart:io';
import 'dart:typed_data';

import 'package:file_selector/file_selector.dart';

class PngExportService {
  const PngExportService();

  Future<String?> export(Uint8List bytes, {DateTime? now}) async {
    final filename = suggestedPngFilename(now ?? DateTime.now());
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

String suggestedPngFilename(DateTime time) {
  String twoDigits(int value) => value.toString().padLeft(2, '0');
  return 'jianpu-keyboard-${time.year}${twoDigits(time.month)}${twoDigits(time.day)}-'
      '${twoDigits(time.hour)}${twoDigits(time.minute)}${twoDigits(time.second)}.png';
}
