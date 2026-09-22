import 'dart:math';

import '../models/music_token.dart';
import '../models/score.dart';
import '../syntax/jianpu_syntax.dart';
import 'display_width.dart';

/// One on-screen column: a score token and the lyric shown under it.
class RenderCell {
  final String letterText;
  final String lyricText;
  final bool isMeasureBar;

  const RenderCell({
    required this.letterText,
    required this.lyricText,
    this.isMeasureBar = false,
  });

  factory RenderCell.fromToken(MusicToken token) {
    return switch (token) {
      Note(
        :final keyboardKey,
        :final lyric,
        :final isLyricContinuation,
      ) =>
        RenderCell(
          letterText: keyboardKey ?? '',
          lyricText:
              isLyricContinuation ? JianpuSyntax.holdSymbol : lyric ?? '',
        ),
      Rest() => const RenderCell(
          letterText: JianpuSyntax.restSymbol,
          lyricText: '',
        ),
      Hold() => const RenderCell(
          letterText: JianpuSyntax.holdSymbol,
          lyricText: '',
        ),
      MeasureBar() => const RenderCell(
          letterText: JianpuSyntax.measureBar,
          lyricText: JianpuSyntax.measureBar,
          isMeasureBar: true,
        ),
    };
  }

  int get columnWidth => max(
        displayWidth(letterText),
        displayWidth(lyricText),
      );
}

/// Renders a structured [Score] as plain text keyboard Jianpu.
class PlainTextRenderer {
  const PlainTextRenderer();

  String render(Score score) {
    final blocks = <String>[];
    for (final line in score.lines) {
      if (line.tokens.isEmpty) {
        continue;
      }
      final cells = [
        for (final token in line.tokens) RenderCell.fromToken(token),
      ];
      final widths = [for (final cell in cells) cell.columnWidth];
      final hasLyricLine = line.tokens.any(_noteHasLyric);

      if (hasLyricLine) {
        blocks.add(_renderRow(
          [for (final cell in cells) cell.letterText],
          widths,
        ));
        blocks.add(_renderRow(
          [for (final cell in cells) cell.lyricText],
          widths,
        ));
      } else {
        blocks.add([for (final cell in cells) cell.letterText].join(' '));
      }
    }
    return blocks.join('\n');
  }

  String _renderRow(List<String> texts, List<int> widths) {
    final parts = <String>[
      for (var i = 0; i < texts.length; i++)
        padToDisplayWidth(texts[i], widths[i]),
    ];
    return parts.join(' ').trimRight();
  }

  bool _noteHasLyric(MusicToken token) {
    return token is Note && token.lyric != null && token.lyric!.isNotEmpty;
  }
}
