/// One lyrics token: either a syllable or a structural measure bar.
class LyricToken {
  final int line;
  final int elementIndex;
  final String rawText;
  final bool isMeasureBar;
  final String? syllable;

  const LyricToken({
    required this.line,
    required this.elementIndex,
    required this.rawText,
    required this.isMeasureBar,
    this.syllable,
  });

  bool get isSyllable =>
      !isMeasureBar && syllable != null && syllable!.isNotEmpty;
}

/// One lyrics line after tokenization.
class LyricLine {
  final int lineNumber;
  final List<LyricToken> tokens;

  const LyricLine({
    required this.lineNumber,
    required this.tokens,
  });

  Iterable<LyricToken> get syllables =>
      tokens.where((token) => token.isSyllable);
}
