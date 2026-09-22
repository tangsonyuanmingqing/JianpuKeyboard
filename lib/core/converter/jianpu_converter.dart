import '../lyrics/lyric_alignment.dart';
import '../mapping/keyboard_mapping.dart';
import '../models/conversion_result.dart';
import '../models/parse_result.dart';
import '../parser/jianpu_parser.dart';
import '../renderer/plain_text_renderer.dart';
import '../validation/score_validator.dart';

/// Orchestrates parse → align → validate → map → render.
class JianpuConverter {
  final JianpuParser parser;
  final LyricAlignmentService lyricAlignment;
  final ScoreValidator validator;
  final KeyboardMapping mapping;
  final PlainTextRenderer renderer;

  const JianpuConverter({
    this.parser = const JianpuParser(),
    this.lyricAlignment = const LyricAlignmentService(),
    this.validator = const ScoreValidator(),
    this.mapping = const KeyboardMapping(),
    this.renderer = const PlainTextRenderer(),
  });

  ConversionResult convert({
    required String scoreText,
    String lyricsText = '',
  }) {
    if (scoreText.trim().isEmpty && lyricsText.trim().isEmpty) {
      return const ConversionResult(output: '');
    }

    final parsed = parser.parse(scoreText: scoreText, lyricsText: lyricsText);
    switch (parsed) {
      case ParseFailure(:final errors):
        return ConversionResult(output: '', errors: errors);
      case ParseSuccess(:final score, :final lyricLines):
        final aligned = lyricAlignment.align(score, lyricLines);
        final validation = validator.validate(
          score: aligned,
          lyricLines: lyricLines,
        );
        final mapped = mapping.apply(aligned);
        return ConversionResult(
          output: renderer.render(mapped),
          warnings: validation.warnings,
          unmatchedLyrics: validation.unmatchedLyrics,
          unmatchedLyricTokens: validation.unmatchedLyricTokens,
          missingLyricNotePositions: validation.missingLyricNotePositions,
          score: mapped,
        );
    }
  }
}
