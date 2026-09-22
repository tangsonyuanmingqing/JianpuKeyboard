/// A whitespace-delimited token with its location in the source line.
class RawToken {
  final String text;
  final int line;
  final int column;
  final int tokenIndex;

  const RawToken({
    required this.text,
    required this.line,
    required this.column,
    required this.tokenIndex,
  });
}

/// Splits a source line into raw tokens while preserving positions.
class JianpuTokenizer {
  static final _tokenPattern = RegExp(r'\S+');

  const JianpuTokenizer();

  List<RawToken> tokenizeLine(
    String line,
    int lineNumber, {
    int columnOffset = 0,
  }) {
    final tokens = <RawToken>[];
    var tokenIndex = 0;
    for (final match in _tokenPattern.allMatches(line)) {
      tokenIndex += 1;
      tokens.add(
        RawToken(
          text: match.group(0)!,
          line: lineNumber,
          column: columnOffset + match.start + 1,
          tokenIndex: tokenIndex,
        ),
      );
    }
    return tokens;
  }
}
