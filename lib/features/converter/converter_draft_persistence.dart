import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../../infrastructure/app_data_store.dart';
import '../../infrastructure/persistence_load_result.dart';
import 'converter_input.dart';
import 'smart_grid_document.dart';

class ConverterDraftLoadResult {
  const ConverterDraftLoadResult(
    this.input, {
    this.wasRestored = false,
    this.message,
    this.songTitle = '',
    this.songId,
    this.gridDocument,
    this.editorMode = 'text',
    this.status = PersistenceLoadStatus.missing,
    this.rawData,
    this.migrated = false,
  });

  final ConverterInput input;
  final String songTitle;
  final String? songId;
  final SmartGridDocument? gridDocument;
  final String editorMode;
  final bool wasRestored;
  final String? message;
  final PersistenceLoadStatus status;
  final String? rawData;
  final bool migrated;

  bool get blocksWrites =>
      status == PersistenceLoadStatus.corrupt ||
      status == PersistenceLoadStatus.migrationFailed;
}

class ConverterDraftPersistence {
  static const legacyKey = 'jianpu_keyboard.converter_draft.v1';
  static const primaryPath = 'storage/v1/converter_draft.json';

  ConverterDraftPersistence({
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

  Future<ConverterDraftLoadResult> load() async {
    if (_legacyOnly) return _loadLegacy(migrate: false);
    final raw = await _store.read(primaryPath);
    if (raw != null) {
      try {
        return decodeDocument(raw, status: PersistenceLoadStatus.normal);
      } on Object {
        return ConverterDraftLoadResult(
          const ConverterInput(),
          message: '当前草稿数据已损坏，请从恢复中心恢复。',
          status: PersistenceLoadStatus.corrupt,
          rawData: raw,
        );
      }
    }
    return _loadLegacy(migrate: true);
  }

  Future<ConverterDraftLoadResult> _loadLegacy({required bool migrate}) async {
    final raw = await _legacyPreferences.getString(legacyKey);
    if (raw == null) return const ConverterDraftLoadResult(ConverterInput());
    try {
      final result = decodeDocument(raw, status: PersistenceLoadStatus.normal);
      if (!migrate) return result;
      try {
        await _store.write(primaryPath, encodeResult(result));
        return _copyWith(result, migrated: true);
      } on Object {
        return _copyWith(
          result,
          status: PersistenceLoadStatus.migrationFailed,
          rawData: raw,
          message: '草稿迁移失败。旧草稿仍保留，修复前不会覆盖。',
        );
      }
    } on Object {
      return ConverterDraftLoadResult(
        const ConverterInput(),
        message: '旧草稿数据已损坏，请先导出原始数据。',
        status: PersistenceLoadStatus.corrupt,
        rawData: raw,
      );
    }
  }

  Future<void> save(
    ConverterInput input, {
    String songTitle = '',
    String? songId,
    SmartGridDocument? gridDocument,
    String editorMode = 'text',
  }) {
    final contents = encodeDocument(
      input,
      songTitle: songTitle,
      songId: songId,
      gridDocument: gridDocument,
      editorMode: editorMode,
    );
    return _writes.run(() async {
      if (_legacyOnly) {
        await _legacyPreferences.setString(legacyKey, contents);
      } else {
        await _store.write(primaryPath, contents);
      }
    });
  }

  Future<void> restoreRaw(String raw) => _writes.run(() async {
        decodeDocument(raw, status: PersistenceLoadStatus.normal);
        if (_legacyOnly) {
          await _legacyPreferences.setString(legacyKey, raw);
        } else {
          await _store.write(primaryPath, raw);
        }
      });

  Future<void> clear() => _writes.run(() async {
        if (_legacyOnly) {
          await _legacyPreferences.remove(legacyKey);
        } else {
          await _store.delete(primaryPath);
        }
      });

  Future<void> flush() => _writes.flush();

  static String encodeDocument(
    ConverterInput input, {
    String songTitle = '',
    String? songId,
    SmartGridDocument? gridDocument,
    String editorMode = 'text',
  }) =>
      jsonEncode({
        'version': 1,
        'scoreText': input.scoreText,
        'lyricsText': input.lyricsText,
        'songTitle': songTitle,
        'songId': songId,
        'gridDocument': gridDocument?.toJson(),
        'editorMode': editorMode,
      });

  static String encodeResult(ConverterDraftLoadResult result) => encodeDocument(
        result.input,
        songTitle: result.songTitle,
        songId: result.songId,
        gridDocument: result.gridDocument,
        editorMode: result.editorMode,
      );

  static ConverterDraftLoadResult decodeDocument(
    String raw, {
    PersistenceLoadStatus status = PersistenceLoadStatus.normal,
  }) {
    final decoded = jsonDecode(raw);
    if (decoded is! Map) throw const FormatException('草稿格式无效。');
    final version = decoded['version'];
    if (version != null && version != 1) {
      throw const FormatException('草稿版本不受支持。');
    }
    final scoreText = decoded['scoreText'];
    final lyricsText = decoded['lyricsText'];
    if (scoreText is! String || lyricsText is! String) {
      throw const FormatException('草稿内容无效。');
    }
    final input = ConverterInput(scoreText: scoreText, lyricsText: lyricsText);
    final rawGrid = decoded['gridDocument'];
    final gridDocument =
        rawGrid == null ? null : SmartGridDocument.fromJson(rawGrid);
    final rawSongTitle = decoded['songTitle'];
    final rawSongId = decoded['songId'];
    final rawMode = decoded['editorMode'];
    return ConverterDraftLoadResult(
      input,
      wasRestored: scoreText.trim().isNotEmpty ||
          lyricsText.trim().isNotEmpty ||
          (rawSongTitle is String && rawSongTitle.trim().isNotEmpty) ||
          (gridDocument?.isEmpty == false),
      songTitle: rawSongTitle is String ? rawSongTitle : '',
      songId: rawSongId is String && rawSongId.isNotEmpty ? rawSongId : null,
      gridDocument: gridDocument,
      editorMode: rawMode == 'grid' ? 'grid' : 'text',
      status: status,
    );
  }

  static ConverterDraftLoadResult _copyWith(
    ConverterDraftLoadResult result, {
    PersistenceLoadStatus? status,
    String? rawData,
    String? message,
    bool migrated = false,
  }) =>
      ConverterDraftLoadResult(
        result.input,
        wasRestored: result.wasRestored,
        message: message ?? result.message,
        songTitle: result.songTitle,
        songId: result.songId,
        gridDocument: result.gridDocument,
        editorMode: result.editorMode,
        status: status ?? result.status,
        rawData: rawData,
        migrated: migrated,
      );
}
