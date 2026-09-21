import '../models/lyric_line.dart';
import '../models/music_token.dart';
import '../models/score.dart';
import '../models/validation_message.dart';

/// Global lyric-count check. Conversion still produces output.
class ScoreValidation {
  final List<ValidationMessage> warnings;
  final List<String> unmatchedLyrics;

  const ScoreValidation({
    this.warnings = const [],
    this.unmatchedLyrics = const [],
  });
}

/// Validates lyric-to-note correspondence without blocking conversion.
class ScoreValidator {
  static const missingLyricsMessage = '歌词少于可对应音符数量，部分音符没有歌词。';
  static const extraLyricsMessage = '歌词数量多于可对应的音符。';

  const ScoreValidator();

  ScoreValidation validate({
    required Score score,
    required List<LyricLine> lyricLines,
  }) {
    final noteCount = _consumableNoteCount(score);
    final syllables = [
      for (final line in lyricLines) ...line.syllables,
    ];
    final lyricCount = syllables.length;

    // Empty or whitespace-only lyrics are "no lyrics provided".
    if (lyricCount == 0) {
      return const ScoreValidation();
    }

    if (lyricCount == noteCount) {
      return const ScoreValidation();
    }

    if (lyricCount < noteCount) {
      return const ScoreValidation(
        warnings: [
          ValidationMessage(line: 0, message: missingLyricsMessage),
        ],
      );
    }

    return ScoreValidation(
      warnings: const [
        ValidationMessage(line: 0, message: extraLyricsMessage),
      ],
      unmatchedLyrics: [
        for (final token in syllables.skip(noteCount)) token.syllable!,
      ],
    );
  }

  int _consumableNoteCount(Score score) {
    var count = 0;
    for (final line in score.lines) {
      count += line.tokens.whereType<Note>().length;
    }
    return count;
  }
}
