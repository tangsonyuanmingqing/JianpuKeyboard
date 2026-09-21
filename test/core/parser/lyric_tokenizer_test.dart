import 'package:flutter_test/flutter_test.dart';
import 'package:jianpu_keyboard/core/parser/lyric_tokenizer.dart';
import 'package:jianpu_keyboard/core/syntax/jianpu_syntax.dart';

void main() {
  const tokenizer = LyricTokenizer();

  List<String> syllables(String line) {
    return tokenizer
        .tokenizeLine(line, 1)
        .syllables
        .map((token) => token.syllable!)
        .toList();
  }

  List<String> rawTexts(String line) {
    return tokenizer
        .tokenizeLine(line, 1)
        .tokens
        .map((token) => token.rawText)
        .toList();
  }

  test('splits consecutive Chinese lyrics into characters', () {
    expect(syllables('黑黑的天空'), ['黑', '黑', '的', '天', '空']);
  });

  test('tokenizes space-separated lyrics the same as consecutive Chinese', () {
    expect(syllables('黑 黑 的 天 空'), ['黑', '黑', '的', '天', '空']);
    expect(syllables('黑 黑 的 天 空'), syllables('黑黑的天空'));
  });

  test('treats a standalone hyphen as continuation, not a syllable', () {
    final result = tokenizer.tokenizeLine('-', 1);

    expect(result.tokens, hasLength(1));
    expect(result.tokens.single.rawText, JianpuSyntax.holdSymbol);
    expect(result.tokens.single.isContinuation, isTrue);
    expect(result.tokens.single.isMeasureBar, isFalse);
    expect(result.tokens.single.isSyllable, isFalse);
    expect(result.tokens.single.syllable, isNull);
    expect(result.syllables, isEmpty);
  });

  test('keeps a syllable and spaced continuation as separate tokens', () {
    final result = tokenizer.tokenizeLine('垂 -', 1);

    expect(rawTexts('垂 -'), ['垂', '-']);
    expect(result.tokens[0].isSyllable, isTrue);
    expect(result.tokens[0].syllable, '垂');
    expect(result.tokens[1].isContinuation, isTrue);
    expect(result.tokens[1].isSyllable, isFalse);
    expect(result.syllables.map((token) => token.syllable), ['垂']);
    expect(result.syllables, hasLength(1));
    expect(result.tokens, hasLength(2));
  });

  test('splits a CJK character attached to a continuation', () {
    final result = tokenizer.tokenizeLine('垂-', 1);

    expect(rawTexts('垂-'), ['垂', '-']);
    expect(result.tokens[0].isSyllable, isTrue);
    expect(result.tokens[1].isContinuation, isTrue);
    expect(result.syllables.map((token) => token.syllable), ['垂']);
  });

  test('splits consecutive CJK attached to a continuation', () {
    final result = tokenizer.tokenizeLine('低垂-', 1);

    expect(rawTexts('低垂-'), ['低', '垂', '-']);
    expect(result.tokens[0].isSyllable, isTrue);
    expect(result.tokens[1].isSyllable, isTrue);
    expect(result.tokens[2].isContinuation, isTrue);
    expect(syllables('低垂-'), ['低', '垂']);
  });

  test('splits consecutive Chinese with a trailing continuation', () {
    final result = tokenizer.tokenizeLine('黑黑的天空低垂-', 1);

    expect(
      rawTexts('黑黑的天空低垂-'),
      ['黑', '黑', '的', '天', '空', '低', '垂', '-'],
    );
    expect(result.tokens.last.isContinuation, isTrue);
    expect(
      syllables('黑黑的天空低垂-'),
      ['黑', '黑', '的', '天', '空', '低', '垂'],
    );
  });

  test('keeps multiple spaced continuations after a syllable', () {
    final result = tokenizer.tokenizeLine('垂 - -', 1);

    expect(rawTexts('垂 - -'), ['垂', '-', '-']);
    expect(result.tokens[0].isSyllable, isTrue);
    expect(result.tokens[1].isContinuation, isTrue);
    expect(result.tokens[2].isContinuation, isTrue);
    expect(result.syllables.map((token) => token.syllable), ['垂']);
  });

  test('treats a measure bar as structure, not a syllable', () {
    final result = tokenizer.tokenizeLine('|', 1);

    expect(result.tokens, hasLength(1));
    expect(result.tokens.single.rawText, JianpuSyntax.measureBar);
    expect(result.tokens.single.isMeasureBar, isTrue);
    expect(result.tokens.single.isContinuation, isFalse);
    expect(result.tokens.single.isSyllable, isFalse);
    expect(result.syllables, isEmpty);
  });

  test('splits consecutive Chinese lyrics including 低垂', () {
    expect(
      syllables('黑黑的天空低垂'),
      ['黑', '黑', '的', '天', '空', '低', '垂'],
    );
  });

  test('tokenizes spaced Chinese lyrics the same as consecutive text', () {
    expect(
      syllables('黑 黑 的 天 空 低 垂'),
      ['黑', '黑', '的', '天', '空', '低', '垂'],
    );
    expect(
      syllables('黑 黑 的 天 空 低 垂'),
      syllables('黑黑的天空低垂'),
    );
    expect(
      rawTexts('黑 黑 的 天 空 低 垂 -'),
      rawTexts('黑黑的天空低垂-'),
    );
  });

  test('does not split a Latin hyphenated word as lyric continuation', () {
    final result = tokenizer.tokenizeLine('well-known', 1);

    expect(result.tokens, hasLength(1));
    expect(result.tokens.single.rawText, 'well-known');
    expect(result.tokens.single.isSyllable, isTrue);
    expect(result.tokens.single.isContinuation, isFalse);
    expect(syllables('well-known'), ['well-known']);
  });
}
