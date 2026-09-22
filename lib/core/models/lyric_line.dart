import 'input_segment.dart';

/// One lyrics token: a syllable, a structural measure bar, or a continuation.
class LyricToken {
  final int line;
  final int elementIndex;
  final String rawText;
  final bool isMeasureBar;
  final bool isContinuation;
  final String? syllable;

  const LyricToken({
    required this.line,
    required this.elementIndex,
    required this.rawText,
    required this.isMeasureBar,
    this.isContinuation = false,
    this.syllable,
  });

  bool get isSyllable =>
      !isMeasureBar &&
      !isContinuation &&
      syllable != null &&
      syllable!.isNotEmpty;
}

/// One lyrics line after tokenization.
class LyricLine {
  final int lineNumber;
  final List<LyricToken> tokens;
  final InputSegment? segment;

  const LyricLine({
    required this.lineNumber,
    required this.tokens,
    this.segment,
  });

  Iterable<LyricToken> get syllables =>
      tokens.where((token) => token.isSyllable);
}
