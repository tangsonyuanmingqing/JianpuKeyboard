import '../models/lyric_line.dart';
import '../models/input_segment.dart';
import '../models/music_token.dart';
import '../models/score.dart';
import '../models/source_position.dart';
import '../models/validation_message.dart';
import '../syntax/jianpu_syntax.dart';

/// Global lyric-count check. Conversion still produces output.
class ScoreValidation {
  final List<ValidationMessage> warnings;
  final List<String> unmatchedLyrics;
  final List<LyricToken> unmatchedLyricTokens;
  final List<SourcePosition> missingLyricNotePositions;

  const ScoreValidation({
    this.warnings = const [],
    this.unmatchedLyrics = const [],
    this.unmatchedLyricTokens = const [],
    this.missingLyricNotePositions = const [],
  });
}

/// Validates lyric-to-note correspondence without blocking conversion.
class ScoreValidator {
  static const missingLyricsMessage = '歌词少于可对应音符数量，部分音符没有歌词。';
  static const extraLyricsMessage = '歌词数量多于可对应的音符。';
  static const ignoredLeadingContinuationMessage = '歌词延续标记 `-` 没有可延续的歌词，已忽略。';

  const ScoreValidator();

  ScoreValidation validate({
    required Score score,
    required List<LyricLine> lyricLines,
  }) {
    if (score.lines.any((line) => line.segment != null) ||
        lyricLines.any((line) => line.segment != null)) {
      return _validateStructured(score, lyricLines);
    }
    final noteCount = _consumableNoteCount(score);
    final walked = _walkLyricSlots(lyricLines);
    final slots = walked.slots;
    final warnings = <ValidationMessage>[
      if (walked.ignoredLeadingContinuation)
        const ValidationMessage(
          line: 0,
          message: ignoredLeadingContinuationMessage,
        ),
    ];

    // No syllables and no valid continuations: skip count warnings.
    if (slots.isEmpty) {
      return ScoreValidation(warnings: warnings);
    }

    if (slots.length == noteCount) {
      return ScoreValidation(warnings: warnings);
    }

    if (slots.length < noteCount) {
      return ScoreValidation(
        warnings: [
          ...warnings,
          const ValidationMessage(line: 0, message: missingLyricsMessage),
        ],
        missingLyricNotePositions: _notes(score)
            .skip(slots.length)
            .map((note) => note.position)
            .toList(),
      );
    }

    final unmatchedSlots = slots.skip(noteCount).toList();

    return ScoreValidation(
      warnings: [
        ...warnings,
        const ValidationMessage(line: 0, message: extraLyricsMessage),
      ],
      unmatchedLyrics: [for (final slot in unmatchedSlots) slot.text],
      unmatchedLyricTokens: [for (final slot in unmatchedSlots) slot.token],
    );
  }

  ScoreValidation _validateStructured(
    Score score,
    List<LyricLine> lyricLines,
  ) {
    final lyricsBySegment = <InputSegment, List<LyricLine>>{};
    for (final line in lyricLines) {
      if (line.segment case final segment?) {
        lyricsBySegment.putIfAbsent(segment, () => []).add(line);
      }
    }
    final groupsWithLyrics = {
      for (final segment in lyricsBySegment.keys) segment.group,
    };

    final warnings = <ValidationMessage>[];
    final unmatchedLyrics = <String>[];
    final unmatchedTokens = <LyricToken>[];
    final missingPositions = <SourcePosition>[];
    final seenSegments = <InputSegment>{};

    for (final scoreLine in score.lines) {
      final segment = scoreLine.segment;
      if (segment == null) continue;
      seenSegments.add(segment);
      if (!lyricsBySegment.containsKey(segment) &&
          groupsWithLyrics.contains(segment.group)) {
        warnings.add(
          ValidationMessage(
            line: 0,
            message: '${segment.label}：$missingLyricsMessage',
          ),
        );
        missingPositions.addAll(
            _notes(Score(lines: [scoreLine])).map((note) => note.position));
        continue;
      }
      final validation = validate(
        score: Score(lines: [
          ScoreLine(lineNumber: scoreLine.lineNumber, tokens: scoreLine.tokens),
        ]),
        lyricLines: [
          for (final line in lyricsBySegment[segment] ?? const <LyricLine>[])
            LyricLine(lineNumber: line.lineNumber, tokens: line.tokens),
        ],
      );
      final label = segment.label;
      warnings.addAll([
        for (final warning in validation.warnings)
          ValidationMessage(
              line: warning.line, message: '$label：${warning.message}'),
      ]);
      unmatchedLyrics.addAll(validation.unmatchedLyrics);
      unmatchedTokens.addAll(validation.unmatchedLyricTokens);
      missingPositions.addAll(validation.missingLyricNotePositions);
    }

    for (final entry in lyricsBySegment.entries) {
      if (seenSegments.contains(entry.key)) continue;
      final walked = _walkLyricSlots(entry.value);
      if (walked.slots.isEmpty) continue;
      final segment = entry.key;
      warnings.add(
        ValidationMessage(
          line: 0,
          message: '${segment.label}：$extraLyricsMessage',
        ),
      );
      unmatchedLyrics.addAll([for (final slot in walked.slots) slot.text]);
      unmatchedTokens.addAll([for (final slot in walked.slots) slot.token]);
    }

    return ScoreValidation(
      warnings: warnings,
      unmatchedLyrics: unmatchedLyrics,
      unmatchedLyricTokens: unmatchedTokens,
      missingLyricNotePositions: missingPositions,
    );
  }

  /// Syllables always occupy a slot. A continuation occupies a slot only when
  /// a previous syllable exists. Leading continuations do not count.
  ({List<_LyricSlot> slots, bool ignoredLeadingContinuation}) _walkLyricSlots(
    List<LyricLine> lyricLines,
  ) {
    final slots = <_LyricSlot>[];
    String? previousSyllable;
    var ignoredLeadingContinuation = false;

    for (final line in lyricLines) {
      for (final token in line.tokens) {
        if (token.isMeasureBar) {
          continue;
        }

        if (token.isContinuation) {
          if (previousSyllable != null) {
            slots.add(_LyricSlot(JianpuSyntax.holdSymbol, token));
          } else {
            ignoredLeadingContinuation = true;
          }
          continue;
        }

        if (token.isSyllable) {
          previousSyllable = token.syllable;
          slots.add(_LyricSlot(token.syllable!, token));
        }
      }
    }

    return (
      slots: slots,
      ignoredLeadingContinuation: ignoredLeadingContinuation,
    );
  }

  int _consumableNoteCount(Score score) => _notes(score).length;

  List<Note> _notes(Score score) => [
        for (final line in score.lines) ...line.tokens.whereType<Note>(),
      ];
}

class _LyricSlot {
  final String text;
  final LyricToken token;

  const _LyricSlot(this.text, this.token);
}
