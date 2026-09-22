import '../models/lyric_line.dart';
import '../models/input_segment.dart';
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

  LyricLine tokenizeLine(
    String line,
    int lineNumber, {
    InputSegment? segment,
  }) {
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

      if (raw.text == JianpuSyntax.holdSymbol) {
        elementIndex += 1;
        tokens.add(
          LyricToken(
            line: lineNumber,
            elementIndex: elementIndex,
            rawText: raw.text,
            isMeasureBar: false,
            isContinuation: true,
          ),
        );
        continue;
      }

      if (_isPunctuationOnly(raw.text)) {
        continue;
      }

      for (final piece in _splitLyricPieces(raw.text)) {
        if (piece.text.isEmpty ||
            (!piece.isContinuation && _isPunctuationOnly(piece.text))) {
          continue;
        }
        elementIndex += 1;
        tokens.add(
          LyricToken(
            line: lineNumber,
            elementIndex: elementIndex,
            rawText: piece.text,
            isMeasureBar: false,
            isContinuation: piece.isContinuation,
            syllable: piece.isContinuation ? null : piece.text,
          ),
        );
      }
    }
    return LyricLine(
      lineNumber: lineNumber,
      tokens: tokens,
      segment: segment,
    );
  }

  List<({String text, bool isContinuation})> _splitLyricPieces(String text) {
    const continuation = JianpuSyntax.holdSymbol;
    var continuationCount = 0;
    var prefixEnd = text.length;
    while (prefixEnd > 0 &&
        text.substring(prefixEnd - 1, prefixEnd) == continuation) {
      prefixEnd -= 1;
      continuationCount += 1;
    }
    final prefix = text.substring(0, prefixEnd);

    if (continuationCount > 0 && prefix.isNotEmpty && _isAllCjk(prefix)) {
      return [
        for (final character in _characters(prefix))
          (text: character, isContinuation: false),
        ...List.filled(
          continuationCount,
          (text: continuation, isContinuation: true),
        ),
      ];
    }

    if (text.length > 1 && _isAllCjk(text)) {
      return [
        for (final character in _characters(text))
          (text: character, isContinuation: false),
      ];
    }

    return [(text: text, isContinuation: false)];
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
