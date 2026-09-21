import 'parse_error.dart';
import 'score.dart';
import 'validation_message.dart';

/// Final converter output shown to the user.
class ConversionResult {
  final String output;
  final List<ParseError> errors;
  final List<ValidationMessage> warnings;
  final List<String> unmatchedLyrics;
  final Score? score;

  const ConversionResult({
    required this.output,
    this.errors = const [],
    this.warnings = const [],
    this.unmatchedLyrics = const [],
    this.score,
  });

  bool get hasErrors => errors.isNotEmpty;
  bool get hasWarnings => warnings.isNotEmpty;
  bool get isEmpty => output.trim().isEmpty;
}
