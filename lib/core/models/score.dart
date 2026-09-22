import 'music_token.dart';
import 'input_segment.dart';

/// One logical line of parsed score tokens.
class ScoreLine {
  final int lineNumber;
  final List<MusicToken> tokens;
  final InputSegment? segment;

  const ScoreLine({
    required this.lineNumber,
    required this.tokens,
    this.segment,
  });
}

/// Structured Jianpu score.
class Score {
  final List<ScoreLine> lines;

  const Score({required this.lines});

  bool get isEmpty => lines.every((line) => line.tokens.isEmpty);
}
