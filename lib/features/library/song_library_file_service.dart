import 'dart:io';

import 'package:file_selector/file_selector.dart';

class SongLibraryFileService {
  const SongLibraryFileService();

  Future<String?> saveJson(String contents,
      {String suggestedName = 'jianpu-keyboard-songs.json'}) async {
    final location = await getSaveLocation(
      suggestedName: suggestedName,
      acceptedTypeGroups: const [
        XTypeGroup(label: '曲谱库备份', extensions: ['json'])
      ],
    );
    if (location == null) return null;
    await File(location.path).writeAsString(contents, flush: true);
    return location.path;
  }

  Future<String?> openJson() async {
    final file = await openFile(acceptedTypeGroups: const [
      XTypeGroup(label: '曲谱库备份', extensions: ['json'])
    ]);
    return file?.readAsString();
  }
}
