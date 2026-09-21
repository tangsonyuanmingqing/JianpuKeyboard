import '../models/music_token.dart';
import '../models/score.dart';
import '../syntax/jianpu_syntax.dart';

/// Renders a structured [Score] as plain text keyboard Jianpu.
class PlainTextRenderer {
  const PlainTextRenderer();

  String render(Score score) {
    final blocks = <String>[];
    for (final line in score.lines) {
      if (line.tokens.isEmpty) {
        continue;
      }
      blocks.add(_renderKeys(line));
      final lyrics = _renderLyrics(line);
      if (lyrics.isNotEmpty) {
        blocks.add(lyrics);
      }
    }
    return blocks.join('\n');
  }

  String _renderKeys(ScoreLine line) {
    return [
      for (final token in line.tokens) _keyText(token),
    ].join(' ');
  }

  String _keyText(MusicToken token) {
    return switch (token) {
      Note(:final keyboardKey) => keyboardKey ?? '',
      Rest() => JianpuSyntax.restSymbol,
      Hold() => JianpuSyntax.holdSymbol,
      MeasureBar() => JianpuSyntax.measureBar,
    };
  }

  String _renderLyrics(ScoreLine line) {
    final hasLyric = line.tokens.any(
      (token) =>
          token is Note && token.lyric != null && token.lyric!.isNotEmpty,
    );
    if (!hasLyric) {
      return '';
    }

    final parts = <String>[];
    for (final token in line.tokens) {
      switch (token) {
        case Note(:final lyric) when lyric != null && lyric.isNotEmpty:
          parts.add(lyric);
        case MeasureBar():
          parts.add(JianpuSyntax.measureBar);
        default:
          break;
      }
    }
    return parts.join(' ');
  }
}
