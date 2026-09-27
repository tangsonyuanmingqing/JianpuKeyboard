import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../../infrastructure/app_data_store.dart';
import '../../infrastructure/persistence_load_result.dart';
import 'song_record.dart';

class SongLibraryPersistence {
  static const storageKey = 'jianpu_keyboard.song_library.v1';
  static const documentVersion = 2;
  static const primaryPath = 'storage/v1/song_library.json';

  SongLibraryPersistence({
    SharedPreferencesAsync? preferences,
    AtomicFileStore? store,
  })  : _preferences = preferences,
        _store = store ?? AtomicFileStore(),
        _legacyOnly = preferences != null && store == null;

  SharedPreferencesAsync? _preferences;
  final AtomicFileStore _store;
  final bool _legacyOnly;
  final SerialOperationQueue _writes = SerialOperationQueue();

  SharedPreferencesAsync get _legacyPreferences =>
      _preferences ??= SharedPreferencesAsync();

  Future<List<SongRecord>> load() async => (await loadDetailed()).value;

  Future<PersistenceLoadResult<List<SongRecord>>> loadDetailed() async {
    if (_legacyOnly) return _loadLegacy(migrate: false);
    final raw = await _store.read(primaryPath);
    if (raw != null) {
      try {
        return PersistenceLoadResult(
          value: decodeDocument(raw),
          status: PersistenceLoadStatus.normal,
        );
      } on Object {
        return PersistenceLoadResult(
          value: const [],
          status: PersistenceLoadStatus.corrupt,
          rawData: raw,
          message: '曲谱库数据已损坏，请从恢复中心恢复。',
        );
      }
    }
    return _loadLegacy(migrate: true);
  }

  Future<PersistenceLoadResult<List<SongRecord>>> _loadLegacy({
    required bool migrate,
  }) async {
    final raw = await _legacyPreferences.getString(storageKey);
    if (raw == null) {
      return const PersistenceLoadResult(
        value: [],
        status: PersistenceLoadStatus.missing,
      );
    }
    try {
      final songs = decodeDocument(raw);
      if (!migrate) {
        return PersistenceLoadResult(
          value: songs,
          status: PersistenceLoadStatus.normal,
        );
      }
      try {
        await _store.write(primaryPath, raw);
        return PersistenceLoadResult(
          value: songs,
          status: PersistenceLoadStatus.normal,
          migrated: true,
        );
      } on Object {
        return PersistenceLoadResult(
          value: songs,
          status: PersistenceLoadStatus.migrationFailed,
          rawData: raw,
          message: '曲谱库迁移失败。旧数据仍保留，修复前不会覆盖。',
        );
      }
    } on Object {
      return PersistenceLoadResult(
        value: const [],
        status: PersistenceLoadStatus.corrupt,
        rawData: raw,
        message: '旧曲谱库数据已损坏，请先导出原始数据。',
      );
    }
  }

  Future<void> save(List<SongRecord> songs) => _writes.run(() async {
        final encoded = encodeDocument(songs);
        if (_legacyOnly) {
          await _legacyPreferences.setString(storageKey, encoded);
        } else {
          await _store.write(primaryPath, encoded);
        }
      });

  Future<void> reset() => save(const []);

  Future<void> flush() => _writes.flush();

  static String encodeDocument(List<SongRecord> songs) => jsonEncode({
        'version': documentVersion,
        'songs': songs.map((song) => song.toJson()).toList(),
      });

  static List<SongRecord> decodeDocument(String raw) {
    final decoded = jsonDecode(raw);
    if (decoded is! Map ||
        (decoded['version'] != 1 && decoded['version'] != documentVersion) ||
        decoded['songs'] is! List) {
      throw const FormatException('不是受支持的曲谱库备份文件。');
    }
    final songs = <SongRecord>[];
    final ids = <String>{};
    for (final item in decoded['songs'] as List) {
      final song = SongRecord.fromJson(item);
      if (song == null || !ids.add(song.id)) {
        throw const FormatException('备份中存在损坏或重复的歌曲记录。');
      }
      songs.add(song);
    }
    return List.unmodifiable(songs);
  }
}
