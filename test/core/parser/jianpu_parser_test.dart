import 'package:flutter_test/flutter_test.dart';
import 'package:jianpu_keyboard/core/models/music_token.dart';
import 'package:jianpu_keyboard/core/models/parse_result.dart';
import 'package:jianpu_keyboard/core/models/register.dart';
import 'package:jianpu_keyboard/core/parser/jianpu_parser.dart';

void main() {
  const parser = JianpuParser();

  test('parses middle, high and low notes', () {
    final result = parser.parse(scoreText: "1 1' 1,");
    expect(result, isA<ParseSuccess>());
    final score = (result as ParseSuccess).score;
    final notes = score.lines.single.tokens.whereType<Note>().toList();
    expect(notes[0].degree, 1);
    expect(notes[0].register, Register.middle);
    expect(notes[1].degree, 1);
    expect(notes[1].register, Register.high);
    expect(notes[2].degree, 1);
    expect(notes[2].register, Register.low);
  });

  test('parses rest, hold and measure bar', () {
    final result = parser.parse(scoreText: '3 0 - | 4');
    final tokens = (result as ParseSuccess).score.lines.single.tokens;
    expect(tokens[0], isA<Note>());
    expect(tokens[1], isA<Rest>());
    expect(tokens[2], isA<Hold>());
    expect(tokens[3], isA<MeasureBar>());
    expect(tokens[4], isA<Note>());
  });

  test('allows extra spaces and tabs', () {
    final result = parser.parse(scoreText: '3\t\t4   5');
    expect(result, isA<ParseSuccess>());
    expect((result as ParseSuccess).score.lines.single.tokens, hasLength(3));
  });

  test('returns a locatable error for 1#', () {
    final result = parser.parse(scoreText: '1#');
    expect(result, isA<ParseFailure>());
    final error = (result as ParseFailure).errors.single;
    expect(error.line, 1);
    expect(error.column, 1);
    expect(error.tokenIndex, 1);
    expect(error.token, '1#');
    expect(error.message, '第 1 行第 1 个元素无法识别：1#');
  });

  test('returns a locatable error for 2\'\'', () {
    final result = parser.parse(scoreText: "2''");
    final error = (result as ParseFailure).errors.single;
    expect(error.message, "第 1 行第 1 个元素无法识别：2''");
  });

  test('returns a locatable error for abc', () {
    final result = parser.parse(scoreText: 'abc');
    final error = (result as ParseFailure).errors.single;
    expect(error.message, '第 1 行第 1 个元素无法识别：abc');
  });

  test('reports the original line number for a later illegal token', () {
    final result = parser.parse(scoreText: '3 4\n1#');
    final error = (result as ParseFailure).errors.single;
    expect(error.line, 2);
    expect(error.column, 1);
    expect(error.tokenIndex, 1);
    expect(error.token, '1#');
    expect(error.message, '第 2 行第 1 个元素无法识别：1#');
  });

  test('collects every unrecognized token', () {
    final result = parser.parse(scoreText: '3 1# abc');
    final errors = (result as ParseFailure).errors;
    expect(errors, hasLength(2));
    expect(errors[0].token, '1#');
    expect(errors[0].tokenIndex, 2);
    expect(errors[0].column, 3);
    expect(errors[1].token, 'abc');
    expect(errors[1].tokenIndex, 3);
    expect(errors[1].column, 6);
  });

  test('reports tokenIndex and a different character column for 1#', () {
    final result = parser.parse(scoreText: '3 4 1# 5');
    expect(result, isA<ParseFailure>());
    final error = (result as ParseFailure).errors.single;
    expect(error.line, 1);
    expect(error.token, '1#');
    expect(error.tokenIndex, 3);
    expect(error.column, 5);
    expect(error.tokenIndex, isNot(error.column));
    expect(error.message, '第 1 行第 3 个元素无法识别：1#');
  });

  test('retains the source column after an inline score header', () {
    final result = parser.parse(scoreText: '[谱]   3 1#');
    final error = (result as ParseFailure).errors.single;

    expect(error.line, 1);
    expect(error.tokenIndex, 2);
    expect(error.column, 9);
    expect(error.token, '1#');
  });

  test('records character columns on successfully parsed notes', () {
    final result = parser.parse(scoreText: '3 4 5');
    final tokens = (result as ParseSuccess).score.lines.single.tokens;
    expect(tokens[0].position.line, 1);
    expect(tokens[0].position.tokenIndex, 1);
    expect(tokens[0].position.column, 1);
    expect(tokens[1].position.tokenIndex, 2);
    expect(tokens[1].position.column, 3);
    expect(tokens[2].position.tokenIndex, 3);
    expect(tokens[2].position.column, 5);
  });

  test('parses standard [谱] and [词] document', () {
    const document = '''
[谱]
3 4 5

[词]
我 爱 你
''';
    final result = parser.parse(scoreText: document);
    expect(result, isA<ParseSuccess>());
    final success = result as ParseSuccess;
    expect(success.score.lines.single.tokens, hasLength(3));
    expect(success.lyricLines.single.syllables, hasLength(3));
  });
}
