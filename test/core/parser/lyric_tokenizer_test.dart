import 'package:flutter_test/flutter_test.dart';
import 'package:jianpu_keyboard/core/parser/lyric_tokenizer.dart';

void main() {
  const tokenizer = LyricTokenizer();

  List<String> syllables(String line) {
    return tokenizer
        .tokenizeLine(line, 1)
        .syllables
        .map((token) => token.syllable!)
        .toList();
  }

  test('splits consecutive Chinese lyrics into characters', () {
    expect(syllables('黑黑的天空'), ['黑', '黑', '的', '天', '空']);
  });

  test('tokenizes space-separated lyrics the same as consecutive Chinese', () {
    expect(syllables('黑 黑 的 天 空'), ['黑', '黑', '的', '天', '空']);
    expect(syllables('黑 黑 的 天 空'), syllables('黑黑的天空'));
  });
}
