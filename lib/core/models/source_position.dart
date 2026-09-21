/// Location of a token in the original input text.
class SourcePosition {
  /// 1-based line number in the source that produced this token.
  final int line;

  /// 1-based character column of the token's first character.
  final int column;

  /// 1-based token order on the source line.
  final int tokenIndex;

  /// Original text of the token.
  final String rawToken;

  const SourcePosition({
    required this.line,
    required this.column,
    required this.tokenIndex,
    required this.rawToken,
  });
}
