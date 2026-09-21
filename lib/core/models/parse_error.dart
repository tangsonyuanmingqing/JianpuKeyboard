/// A locatable parser failure.
class ParseError {
  /// 1-based source line number.
  final int line;

  /// 1-based character column of the token's first character.
  final int column;

  /// 1-based token order on the source line.
  final int tokenIndex;

  final String token;
  final String message;

  const ParseError({
    required this.line,
    required this.column,
    required this.tokenIndex,
    required this.token,
    required this.message,
  });

  factory ParseError.unrecognized({
    required int line,
    required int column,
    required int tokenIndex,
    required String token,
  }) {
    return ParseError(
      line: line,
      column: column,
      tokenIndex: tokenIndex,
      token: token,
      message: '第 $line 行第 $tokenIndex 个元素无法识别：$token',
    );
  }
}
