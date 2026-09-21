import '../models/lyric_line.dart';
import '../models/music_token.dart';
import '../models/score.dart';

/// Aligns lyric tokens onto notes in global source order.
///
/// Notes consume syllables and valid lyric continuations. Rests, holds, measure
/// bars, line breaks, and leading continuations without a previous syllable
/// do not. A valid lyric continuation reuses the previous syllable and does
/// not introduce a new syllable.
/// Missing lyrics leave [Note.lyric] as null. Extra lyrics are left unconsumed.
class LyricAlignmentService {
  const LyricAlignmentService();

  Score align(Score score, List<LyricLine> lyricLines) {
    final lyricTokens = [
      for (final line in lyricLines) ...line.tokens,
    ];
    var lyricIndex = 0;
    String? previousSyllable;

    Note alignNote(Note note) {
      while (lyricIndex < lyricTokens.length) {
        final lyricToken = lyricTokens[lyricIndex];
        if (lyricToken.isMeasureBar) {
          lyricIndex += 1;
          continue;
        }

        lyricIndex += 1;
        if (lyricToken.isContinuation) {
          if (previousSyllable == null) {
            continue;
          }
          return note.copyWith(
            lyric: previousSyllable,
            isLyricContinuation: true,
          );
        }

        if (lyricToken.isSyllable) {
          previousSyllable = lyricToken.syllable;
          return note.copyWith(
            lyric: lyricToken.syllable,
            isLyricContinuation: false,
          );
        }
      }

      return note.copyWith(isLyricContinuation: false);
    }

    final alignedLines = <ScoreLine>[];
    for (final scoreLine in score.lines) {
      final tokens = <MusicToken>[];
      for (final token in scoreLine.tokens) {
        if (token is Note) {
          tokens.add(alignNote(token));
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
