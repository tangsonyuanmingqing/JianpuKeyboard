import 'lyric_line.dart';
import 'parse_error.dart';
import 'score.dart';
import 'validation_message.dart';

/// Outcome of parsing Jianpu text into a structured score.
sealed class ParseResult {
  const ParseResult();
}

class ParseSuccess extends ParseResult {
  final Score score;
  final List<LyricLine> lyricLines;
  final List<ValidationMessage> inputWarnings;

  const ParseSuccess({
    required this.score,
    required this.lyricLines,
    this.inputWarnings = const [],
  });
}

class ParseFailure extends ParseResult {
  final List<ParseError> errors;

  const ParseFailure(this.errors);
}
