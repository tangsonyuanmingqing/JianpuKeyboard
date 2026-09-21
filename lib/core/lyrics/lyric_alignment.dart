import '../models/lyric_line.dart';
import '../models/music_token.dart';
import '../models/score.dart';

/// Aligns lyric syllables onto notes in global source order.
///
/// Notes consume lyrics. Rests, holds, measure bars, and line breaks do not.
/// Missing lyrics leave [Note.lyric] as null. Extra lyrics are left unconsumed.
class LyricAlignmentService {
  const LyricAlignmentService();

  Score align(Score score, List<LyricLine> lyricLines) {
    final syllables = [
      for (final line in lyricLines) ...line.syllables,
    ];
    var lyricIndex = 0;

    final alignedLines = <ScoreLine>[];
    for (final scoreLine in score.lines) {
      final tokens = <MusicToken>[];
      for (final token in scoreLine.tokens) {
        if (token is Note) {
          final lyric = lyricIndex < syllables.length
              ? syllables[lyricIndex++].syllable
              : null;
          tokens.add(token.copyWith(lyric: lyric));
        } else {
          tokens.add(token);
        }
      }
      alignedLines.add(
        ScoreLine(lineNumber: scoreLine.lineNumber, tokens: tokens),
      );
    }

    return Score(lines: alignedLines);
  }
}
