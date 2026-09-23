import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'song_record.dart';

class SongLibraryPersistence {
  static const storageKey = 'jianpu_keyboard.song_library.v1';
  static const documentVersion = 2;
  final SharedPreferencesAsync _preferences;

  SongLibraryPersistence({SharedPreferencesAsync? preferences})
      : _preferences = preferences ?? SharedPreferencesAsync();

  Future<List<SongRecord>> load() async {
    final raw = await _preferences.getString(storageKey);
    if (raw == null) return const [];
    return decodeDocument(raw);
  }

  Future<void> save(List<SongRecord> songs) =>
      _preferences.setString(storageKey, encodeDocument(songs));

  static String encodeDocument(List<SongRecord> songs) => jsonEncode({
        'version': documentVersion,
        'songs': songs.map((song) => song.toJson()).toList()
      });

  static List<SongRecord> decodeDocument(String raw) {
    final decoded = jsonDecode(raw);
    if (decoded is! Map ||
        (decoded['version'] != 1 && decoded['version'] != documentVersion) ||
        decoded['songs'] is! List)
      throw const FormatException('不是受支持的曲谱库备份文件。');
    final songs = <SongRecord>[];
    final ids = <String>{};
    for (final item in decoded['songs'] as List) {
      final song = SongRecord.fromJson(item);
      if (song == null || !ids.add(song.id))
        throw const FormatException('备份中存在损坏或重复的歌曲记录。');
      songs.add(song);
    }
    return List.unmodifiable(songs);
  }
}
