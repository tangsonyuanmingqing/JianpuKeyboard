import 'package:flutter_test/flutter_test.dart';
import 'package:jianpu_keyboard/core/converter/jianpu_converter.dart';
import 'package:jianpu_keyboard/core/models/music_token.dart';
import 'package:jianpu_keyboard/core/models/register.dart';
import 'package:jianpu_keyboard/core/validation/score_validator.dart';

void main() {
  const converter = JianpuConverter();

  test('converts middle-register degrees 3 4 5 6 7', () {
    final result = converter.convert(scoreText: '3 4 5 6 7');
    expect(result.output, 'D F G H J');
    expect(result.errors, isEmpty);
  });

  test('converts high-register notes', () {
    final result = converter.convert(scoreText: "1' 2' 3' 4' 5' 6' 7'");
    expect(result.output, 'Q W E R T Y U');
  });

  test('converts low-register notes', () {
    final result = converter.convert(scoreText: '1, 2, 3, 4, 5, 6, 7,');
    expect(result.output, 'Z X C V B N M');
  });

  test('converts mixed registers', () {
    final result = converter.convert(
      scoreText: "1, 2, 3, 1 2 3 4 5 6 7 1' 2' 3'",
    );
    expect(result.output, 'Z X C A S D F G H J Q W E');
  });

  test('does not treat a middle-register 3 as low after a low-register note',
      () {
    final result = converter.convert(scoreText: "1, 2, 3 4 5 6 7 1' 2' 3'");
    expect(result.output, 'Z X D F G H J Q W E');
  });

  test('converts mixed low, middle and high registers from each token', () {
    final result = converter.convert(
      scoreText: "1, 2, 3, 1 2 3 1' 2' 3'",
    );

    expect(result.errors, isEmpty);
    expect(result.output, 'Z X C A S D Q W E');

    final notes = result.score!.lines.single.tokens.whereType<Note>().toList();
    expect(notes, hasLength(9));

    expect(notes[0].degree, 1);
    expect(notes[0].register, Register.low);
    expect(notes[0].keyboardKey, 'Z');

    expect(notes[1].degree, 2);
    expect(notes[1].register, Register.low);
    expect(notes[1].keyboardKey, 'X');

    expect(notes[2].degree, 3);
    expect(notes[2].register, Register.low);
    expect(notes[2].keyboardKey, 'C');

    expect(notes[3].degree, 1);
    expect(notes[3].register, Register.middle);
    expect(notes[3].keyboardKey, 'A');

    expect(notes[4].degree, 2);
    expect(notes[4].register, Register.middle);
    expect(notes[4].keyboardKey, 'S');

    expect(notes[5].degree, 3);
    expect(notes[5].register, Register.middle);
    expect(notes[5].keyboardKey, 'D');

    expect(notes[6].degree, 1);
    expect(notes[6].register, Register.high);
    expect(notes[6].keyboardKey, 'Q');

    expect(notes[7].degree, 2);
    expect(notes[7].register, Register.high);
    expect(notes[7].keyboardKey, 'W');

    expect(notes[8].degree, 3);
    expect(notes[8].register, Register.high);
    expect(notes[8].keyboardKey, 'E');

    // Register comes from the current token, not the previous one.
    expect(notes[2].register, Register.low);
    expect(notes[3].register, isNot(Register.low));
    expect(notes[5].register, Register.middle);
    expect(notes[6].register, isNot(Register.middle));
  });

  test('preserves measure bars', () {
    final result = converter.convert(scoreText: '3 4 5 | 6 7');
    expect(result.output, 'D F G | H J');
  });

  test('preserves rests without mapping them', () {
    final result = converter.convert(scoreText: '3 0 4');
    expect(result.output, 'D 0 F');
  });

  test('preserves holds without mapping them', () {
    final result = converter.convert(scoreText: '7 - -');
    expect(result.output, 'J - -');
  });

  test('aligns lyrics to notes in standard format', () {
    const document = '''
[谱]
3 4 5

[词]
我 爱 你
''';
    final result = converter.convert(scoreText: document);
    expect(result.output, 'D F G\n我 爱 你');
    expect(result.errors, isEmpty);
  });

  test('uses lyrics field when score document has no [词] section', () {
    final result = converter.convert(
      scoreText: '[谱]\n3 4 5',
      lyricsText: '我 爱 你',
    );
    expect(result.output, 'D F G\n我 爱 你');
  });

  test('does not consume lyrics for holds', () {
    const document = '''
[谱]
3 - -

[词]
我
''';
    final result = converter.convert(scoreText: document);
    expect(result.output, 'D - -\n我');
  });

  test('does not consume lyrics for rests', () {
    final result = converter.convert(
      scoreText: '3 0 4',
      lyricsText: '我 爱',
    );
    expect(result.output, 'D 0 F\n我 爱');
  });

  test('does not fail when lyrics are missing', () {
    final result = converter.convert(
      scoreText: '3 4 5',
      lyricsText: '我',
    );
    expect(result.errors, isEmpty);
    expect(result.warnings, isNotEmpty);
    expect(
      result.warnings.single.message,
      ScoreValidator.missingLyricsMessage,
    );
    expect(result.unmatchedLyrics, isEmpty);
    expect(result.output, 'D F G\n我');
  });

  test('warns but still converts when lyrics are extra', () {
    final result = converter.convert(
      scoreText: '3 4',
      lyricsText: '我 爱 你',
    );
    expect(result.errors, isEmpty);
    expect(result.warnings, isNotEmpty);
    expect(
      result.warnings.single.message,
      ScoreValidator.extraLyricsMessage,
    );
    expect(result.unmatchedLyrics, ['你']);
    expect(result.output, 'D F\n我 爱');
  });

  test('returns a locatable error for illegal tokens', () {
    final result = converter.convert(scoreText: '3 1# abc');
    expect(result.output, isEmpty);
    expect(result.errors.map((error) => error.message), [
      '第 1 行第 2 个元素无法识别：1#',
      '第 1 行第 3 个元素无法识别：abc',
    ]);
  });

  test('converts the sample song with lyrics', () {
    const document = '''
[谱]
3 3 3 4 5 | 3 2 2 -
1 1 1 2 3 | 3 7 7 -

[词]
黑 黑 的 天 空 | 低 垂
亮 亮 的 繁 星 | 相 随
''';
    final result = converter.convert(scoreText: document);
    expect(
      result.output,
      'D D D F G | D S S -\n'
      '黑 黑 的 天 空 | 低 垂 亮\n'
      'A A A S D | D J J -\n'
      '亮 的 繁 星 相 | 随',
    );
  });

  test('splits consecutive Chinese characters as a fallback', () {
    final result = converter.convert(
      scoreText: '3 4 5',
      lyricsText: '我爱你',
    );
    expect(result.output, 'D F G\n我 爱 你');
  });

  test('does not warn when global lyric count matches notes', () {
    final result = converter.convert(
      scoreText: '3 4\n5 6',
      lyricsText: '我 爱\n你 好',
    );
    expect(result.warnings, isEmpty);
    expect(result.unmatchedLyrics, isEmpty);
    expect(result.output, 'D F\n我 爱\nG H\n你 好');
  });

  test('warns and leaves unmatched notes empty when lyrics are short', () {
    final result = converter.convert(
      scoreText: '3 4\n5 6',
      lyricsText: '我 爱',
    );
    expect(result.warnings.single.message, ScoreValidator.missingLyricsMessage);
    expect(result.unmatchedLyrics, isEmpty);
    final notes = result.score!.lines
        .expand((line) => line.tokens)
        .whereType<Note>()
        .toList();
    expect(notes.map((note) => note.lyric), ['我', '爱', null, null]);
  });

  test('does not warn when converting notes without lyrics', () {
    final result = converter.convert(scoreText: '3 4 5');
    expect(result.errors, isEmpty);
    expect(result.warnings, isEmpty);
    expect(result.unmatchedLyrics, isEmpty);
    expect(result.output, 'D F G');
    expect(
      result.score!.lines.single.tokens
          .whereType<Note>()
          .map((note) => note.lyric),
      [null, null, null],
    );
  });

  test('does not warn when lyrics are only whitespace', () {
    final result = converter.convert(
      scoreText: '3 4 5',
      lyricsText: '   ',
    );
    expect(result.errors, isEmpty);
    expect(result.warnings, isEmpty);
    expect(result.unmatchedLyrics, isEmpty);
    expect(result.output, 'D F G');
    expect(
      result.score!.lines.single.tokens
          .whereType<Note>()
          .map((note) => note.lyric),
      [null, null, null],
    );
  });

  test('warns when provided lyrics are fewer than notes', () {
    final result = converter.convert(
      scoreText: '3 4 5 6',
      lyricsText: '我 爱',
    );
    expect(result.errors, isEmpty);
    expect(result.warnings.single.message, ScoreValidator.missingLyricsMessage);
    expect(result.unmatchedLyrics, isEmpty);
    final notes = result.score!.lines.single.tokens.whereType<Note>().toList();
    expect(notes.map((note) => note.lyric), ['我', '爱', null, null]);
  });

  test('does not warn when provided lyrics match notes', () {
    final result = converter.convert(
      scoreText: '3 4 5',
      lyricsText: '我 爱 你',
    );
    expect(result.warnings, isEmpty);
    expect(result.unmatchedLyrics, isEmpty);
    expect(result.output, 'D F G\n我 爱 你');
  });

  test('keeps extra lyrics out of rendered text', () {
    final result = converter.convert(
      scoreText: '3 4 5',
      lyricsText: '我 爱 你 好 吗',
    );
    expect(result.warnings.single.message, ScoreValidator.extraLyricsMessage);
    expect(result.unmatchedLyrics, ['好', '吗']);
    expect(result.output, 'D F G\n我 爱 你');
  });

  test('exposes aligned score, warnings and unmatched lyrics', () {
    final result = converter.convert(
      scoreText: '3 4\n5 6',
      lyricsText: '我 爱 你 好 吗',
    );

    expect(result.errors, isEmpty);
    expect(result.output, 'D F\n我 爱\nG H\n你 好');
    expect(
      result.warnings.single.message,
      ScoreValidator.extraLyricsMessage,
    );
    expect(result.unmatchedLyrics, ['吗']);

    final notes = result.score!.lines
        .expand((line) => line.tokens)
        .whereType<Note>()
        .toList();
    expect(notes.map((note) => note.keyboardKey), ['D', 'F', 'G', 'H']);
    expect(notes.map((note) => note.lyric), ['我', '爱', '你', '好']);
  });
}
