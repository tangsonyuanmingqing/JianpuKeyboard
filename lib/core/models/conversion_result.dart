import 'parse_error.dart';
import 'lyric_line.dart';
import 'score.dart';
import 'source_position.dart';
import 'validation_message.dart';

/// Final converter output shown to the user.
class ConversionResult {
  final String output;
  final List<ParseError> errors;
  final List<ValidationMessage> warnings;
  final List<String> unmatchedLyrics;
  final List<LyricToken> unmatchedLyricTokens;
  final List<SourcePosition> missingLyricNotePositions;
  final Score? score;

  const ConversionResult({
    required this.output,
    this.errors = const [],
    this.warnings = const [],
    this.unmatchedLyrics = const [],
    this.unmatchedLyricTokens = const [],
    this.missingLyricNotePositions = const [],
    this.score,
  });

  bool get hasErrors => errors.isNotEmpty;
  bool get hasWarnings => warnings.isNotEmpty;
  bool get isEmpty => output.trim().isEmpty;
}
