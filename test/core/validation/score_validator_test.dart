import 'package:flutter_test/flutter_test.dart';
import 'package:jianpu_keyboard/core/models/music_token.dart';
import 'package:jianpu_keyboard/core/models/parse_result.dart';
import 'package:jianpu_keyboard/core/parser/jianpu_parser.dart';
import 'package:jianpu_keyboard/core/validation/score_validator.dart';

void main() {
  const validator = ScoreValidator();
  const parser = JianpuParser();

  ScoreValidation validate(String scoreText, [String lyricsText = '']) {
    final parsed = parser.parse(scoreText: scoreText, lyricsText: lyricsText);
    final success = parsed as ParseSuccess;
    return validator.validate(
      score: success.score,
      lyricLines: success.lyricLines,
    );
  }

  int noteCount(String scoreText) {
    final parsed = parser.parse(scoreText: scoreText);
    return (parsed as ParseSuccess)
        .score
        .lines
        .expand((line) => line.tokens)
        .whereType<Note>()
        .length;
  }

  test('does not warn when provided lyrics exactly match notes', () {
    final result = validate('3 4 5', '我 爱 你');
    expect(result.warnings, isEmpty);
    expect(result.unmatchedLyrics, isEmpty);
  });

  test('does not warn when lyric count matches across lines', () {
    final result = validate('3 4\n5 6', '我 爱\n你 好');
    expect(result.warnings, isEmpty);
    expect(result.unmatchedLyrics, isEmpty);
  });

  test('warns when lyrics are fewer than notes', () {
    final result = validate('3 4 5 6', '我 爱');
    expect(result.warnings, hasLength(1));
    expect(
      result.warnings.single.message,
      ScoreValidator.missingLyricsMessage,
    );
    expect(result.unmatchedLyrics, isEmpty);
  });

  test('warns and keeps unmatched lyrics when lyrics are extra', () {
    final result = validate('3 4 5', '我 爱 你 好 吗');
    expect(result.warnings, hasLength(1));
    expect(
      result.warnings.single.message,
      ScoreValidator.extraLyricsMessage,
    );
    expect(result.unmatchedLyrics, ['好', '吗']);
  });

  test('counts notes and lyrics globally across lines', () {
    final result = validate('3 4 5\n6 7', '我 爱\n你 好 吗');
    expect(result.warnings, isEmpty);
    expect(result.unmatchedLyrics, isEmpty);
  });

  test('does not count holds as consumable notes', () {
    expect(noteCount('3 - - 4'), 2);
    final result = validate('3 - - 4', '我 爱');
    expect(result.warnings, isEmpty);
    expect(result.unmatchedLyrics, isEmpty);
  });

  test('does not count rests as consumable notes', () {
    expect(noteCount('3 0 4'), 2);
    final result = validate('3 0 4', '我 爱');
    expect(result.warnings, isEmpty);
    expect(result.unmatchedLyrics, isEmpty);
  });

  test('does not count measure bars as consumable notes', () {
    expect(noteCount('3 4 | 5 6'), 4);
    final result = validate('3 4 | 5 6', '我 爱 你 好');
    expect(result.warnings, isEmpty);
    expect(result.unmatchedLyrics, isEmpty);
  });

  test('does not warn when no lyrics are provided', () {
    final result = validate('3 4 5');
    expect(result.warnings, isEmpty);
    expect(result.unmatchedLyrics, isEmpty);
  });

  test('does not warn when lyrics are only whitespace', () {
    final result = validate('3 4 5', '   ');
    expect(result.warnings, isEmpty);
    expect(result.unmatchedLyrics, isEmpty);
  });

  test(
      'does not warn when eight notes match seven syllables and a continuation',
      () {
    final result = validate(
      '3 3 3 4 5 | 3 2 2 -',
      '黑 黑 的 天 空 | 低 垂 -',
    );
    expect(noteCount('3 3 3 4 5 | 3 2 2 -'), 8);
    expect(result.warnings, isEmpty);
    expect(result.unmatchedLyrics, isEmpty);
  });

  test('warns when eight notes have only seven syllables', () {
    final result = validate(
      '3 3 3 4 5 | 3 2 2 -',
      '黑 黑 的 天 空 | 低 垂',
    );
    expect(result.warnings.single.message, ScoreValidator.missingLyricsMessage);
    expect(result.unmatchedLyrics, isEmpty);
  });

  test(
      'does not warn when one syllable and three continuations fill four notes',
      () {
    final result = validate('3 4 5 6', '我 - - -');
    expect(result.warnings, isEmpty);
    expect(result.unmatchedLyrics, isEmpty);
  });

  test('does not count a leading continuation as a lyric slot', () {
    final result = validate('3', '- 我');
    expect(
      result.warnings.single.message,
      ScoreValidator.ignoredLeadingContinuationMessage,
    );
    expect(result.unmatchedLyrics, isEmpty);
  });

  test('warns about a leading continuation and remaining unmatched notes', () {
    final result = validate('3 4', '- 我');
    expect(
      result.warnings.map((warning) => warning.message),
      [
        ScoreValidator.ignoredLeadingContinuationMessage,
        ScoreValidator.missingLyricsMessage,
      ],
    );
    expect(result.unmatchedLyrics, isEmpty);
  });

  test('warns for each leading continuation without counting them as slots',
      () {
    final result = validate('3 4', '- - 我');
    expect(
      result.warnings.map((warning) => warning.message),
      contains(ScoreValidator.ignoredLeadingContinuationMessage),
    );
    expect(result.unmatchedLyrics, isEmpty);
    expect(
      result.warnings.map((warning) => warning.message),
      contains(ScoreValidator.missingLyricsMessage),
    );
  });

  test('keeps extra continuations in unmatched lyrics', () {
    final result = validate('3 4', '我 爱 -');
    expect(result.warnings.single.message, ScoreValidator.extraLyricsMessage);
    expect(result.unmatchedLyrics, ['-']);
  });
}
