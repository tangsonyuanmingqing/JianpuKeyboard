import 'package:flutter_test/flutter_test.dart';
import 'package:jianpu_keyboard/core/converter/jianpu_converter.dart';

void main() {
  const converter = JianpuConverter();

  test('converts repeated score and lyric groups with sentence and row breaks',
      () {
    final result = converter.convert(
      scoreText: '''
[谱] 3 4 5; 5 4 3 // 1 2
[词] 我爱你;你爱我 // 新歌
[谱] 6 7
[词] 好啊
''',
    );

    expect(result.errors, isEmpty);
    expect(
      result.output,
      'D  F  G\n我 爱 你\nG  F  D\n你 爱 我\nA  S\n新 歌\nH  J\n好 啊',
    );
  });

  test('keeps conversion and identifies a structured lyric mismatch', () {
    final result = converter.convert(
      scoreText: '[谱] 3 4 // 5\n[词] 我 // 你',
    );

    expect(result.errors, isEmpty);
    expect(result.output, 'D  F\n我\nG\n你');
    expect(
      result.warnings.single.message,
      '第 1 组，第 1 句，第 1 行：歌词少于可对应音符数量，部分音符没有歌词。',
    );
  });

  test('reports a missing lyric row within a paired group', () {
    final result = converter.convert(
      scoreText: '[谱] 3; 4\n[词] 我',
    );

    expect(result.errors, isEmpty);
    expect(result.output, 'D\n我\nF');
    expect(
      result.warnings.single.message,
      '第 1 组，第 1 句，第 2 行：歌词少于可对应音符数量，部分音符没有歌词。',
    );
  });

  test('rejects an orphan lyric section and an empty sentence', () {
    final orphan = converter.convert(scoreText: '[词] 我爱你');
    expect(orphan.hasErrors, isTrue);
    expect(orphan.errors.single.message, contains('[词] 前必须先有'));

    final emptySentence = converter.convert(scoreText: '3 4 // // 5 6');
    expect(emptySentence.hasErrors, isTrue);
    expect(emptySentence.errors.single.message, contains('不允许空句或空行'));
  });

  test('warns when inline lyrics override the independent lyric field', () {
    final result = converter.convert(
      scoreText: '[谱] 3 4 // 5\n[词] 我爱 // 你',
      lyricsText: '不会使用',
    );

    expect(result.errors, isEmpty);
    expect(
      result.warnings.any((warning) => warning.message.contains('已忽略独立歌词框')),
      isTrue,
    );
  });
}
