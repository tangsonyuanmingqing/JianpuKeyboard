import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'converter_input.dart';

class ConverterDraftLoadResult {
  final ConverterInput input;
  final String? songId;
  final bool wasRestored;
  final String? message;

  const ConverterDraftLoadResult(
    this.input, {
    this.wasRestored = false,
    this.message,
    this.songId,
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
      return ConverterDraftLoadResult(
        input,
        wasRestored:
            scoreText.trim().isNotEmpty || lyricsText.trim().isNotEmpty,
        songId: rawSongId is String && rawSongId.isNotEmpty ? rawSongId : null,
      );
    } on Object {
      return const ConverterDraftLoadResult(
        ConverterInput(),
        message: '读取上次草稿失败，已从空白输入开始。',
      );
    }
  }

  Future<void> save(ConverterInput input, {String? songId}) =>
      _preferences.setString(
        _key,
        jsonEncode({
          'scoreText': input.scoreText,
          'lyricsText': input.lyricsText,
          'songId': songId
        }),
      );

  Future<void> clear() => _preferences.remove(_key);
}
