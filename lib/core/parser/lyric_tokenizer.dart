import '../models/lyric_line.dart';
import '../syntax/jianpu_syntax.dart';
import 'jianpu_tokenizer.dart';

/// Tokenizes lyric lines using whitespace, with CJK character fallback.
class LyricTokenizer {
  static const _punctuation = {
    ',',
    '.',
    '!',
    '?',
    ';',
    ':',
    '，',
    '。',
    '！',
    '？',
    '、',
    '；',
    '：',
    '"',
    "'",
    '“',
    '”',
    '‘',
    '’',
    '（',
    '）',
    '(',
    ')',
    '[',
    ']',
    '【',
    '】',
    '《',
    '》',
  };

  static final _cjkChar = RegExp(r'[\u4e00-\u9fff]');

  final JianpuTokenizer _tokenizer;

  const LyricTokenizer({
    JianpuTokenizer tokenizer = const JianpuTokenizer(),
  }) : _tokenizer = tokenizer;

  LyricLine tokenizeLine(String line, int lineNumber) {
    final tokens = <LyricToken>[];
    var elementIndex = 0;
    for (final raw in _tokenizer.tokenizeLine(line, lineNumber)) {
      if (raw.text == JianpuSyntax.measureBar) {
        elementIndex += 1;
        tokens.add(
          LyricToken(
            line: lineNumber,
            elementIndex: elementIndex,
            rawText: raw.text,
            isMeasureBar: true,
          ),
        );
        continue;
      }

      if (_isPunctuationOnly(raw.text)) {
        continue;
      }

      for (final syllable in _splitSyllables(raw.text)) {
        if (syllable.isEmpty || _isPunctuationOnly(syllable)) {
          continue;
        }
        elementIndex += 1;
        tokens.add(
          LyricToken(
            line: lineNumber,
            elementIndex: elementIndex,
            rawText: syllable,
            isMeasureBar: false,
            syllable: syllable,
          ),
        );
      }
    }
    return LyricLine(lineNumber: lineNumber, tokens: tokens);
  }

  List<String> _splitSyllables(String text) {
    if (text.length > 1 && _isAllCjk(text)) {
      return _characters(text);
    }
    return [text];
  }

  List<String> _characters(String text) {
    return [for (final rune in text.runes) String.fromCharCode(rune)];
  }

  bool _isAllCjk(String text) {
    for (final rune in text.runes) {
      if (!_cjkChar.hasMatch(String.fromCharCode(rune))) {
        return false;
      }
    }
    return true;
  }

  bool _isPunctuationOnly(String text) {
    if (text.isEmpty) {
      return false;
    }
    return _characters(text).every(_punctuation.contains);
  }
}
