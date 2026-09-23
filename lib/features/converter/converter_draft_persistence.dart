import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'converter_input.dart';
import 'smart_grid_document.dart';

class ConverterDraftLoadResult {
  final ConverterInput input;
  final String? songId;
  final SmartGridDocument? gridDocument;
  final String editorMode;
  final bool wasRestored;
  final String? message;

  const ConverterDraftLoadResult(
    this.input, {
    this.wasRestored = false,
    this.message,
    this.songId,
    this.gridDocument,
    this.editorMode = 'text',
  });
}

/// Stores only user-entered source text. Converted output is always rebuilt.
class ConverterDraftPersistence {
  static const _key = 'jianpu_keyboard.converter_draft.v1';

  final SharedPreferencesAsync _preferences;

  ConverterDraftPersistence({SharedPreferencesAsync? preferences})
      : _preferences = preferences ?? SharedPreferencesAsync();

  Future<ConverterDraftLoadResult> load() async {
    try {
      final raw = await _preferences.getString(_key);
      if (raw == null) {
        return const ConverterDraftLoadResult(ConverterInput());
      }
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) {
        return const ConverterDraftLoadResult(
          ConverterInput(),
          message: '上次草稿无法读取，已从空白输入开始。',
        );
      }
      final scoreText = decoded['scoreText'];
      final lyricsText = decoded['lyricsText'];
      if (scoreText is! String || lyricsText is! String) {
        return const ConverterDraftLoadResult(
          ConverterInput(),
          message: '上次草稿无法读取，已从空白输入开始。',
        );
      }
      final input =
          ConverterInput(scoreText: scoreText, lyricsText: lyricsText);
      final rawSongId = decoded['songId'];
      final rawGrid = decoded['gridDocument'];
      final gridDocument =
          rawGrid == null ? null : SmartGridDocument.fromJson(rawGrid);
      final rawMode = decoded['editorMode'];
      return ConverterDraftLoadResult(
        input,
        wasRestored:
            scoreText.trim().isNotEmpty || lyricsText.trim().isNotEmpty,
        songId: rawSongId is String && rawSongId.isNotEmpty ? rawSongId : null,
        gridDocument: gridDocument,
        editorMode: rawMode == 'grid' ? 'grid' : 'text',
      );
    } on Object {
      return const ConverterDraftLoadResult(
        ConverterInput(),
        message: '读取上次草稿失败，已从空白输入开始。',
      );
    }
  }

  Future<void> save(
    ConverterInput input, {
    String? songId,
    SmartGridDocument? gridDocument,
    String editorMode = 'text',
  }) =>
      _preferences.setString(
        _key,
        jsonEncode({
          'scoreText': input.scoreText,
          'lyricsText': input.lyricsText,
          'songId': songId,
          'gridDocument': gridDocument?.toJson(),
          'editorMode': editorMode,
        }),
      );

  Future<void> clear() => _preferences.remove(_key);
}
