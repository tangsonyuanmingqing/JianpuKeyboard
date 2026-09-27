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
  final int minimumColumnWidth;

  const RenderCell({
    required this.letterText,
    required this.lyricText,
    this.isMeasureBar = false,
    this.minimumColumnWidth = 0,
  });

  factory RenderCell.fromToken(MusicToken token) {
    return switch (token) {
      Note(
        :final keyboardKey,
        :final lyric,
        :final isLyricContinuation,
      ) =>
        RenderCell(
          letterText: toFullwidthKeyboardLetters(keyboardKey ?? ''),
          lyricText:
              isLyricContinuation ? JianpuSyntax.holdSymbol : lyric ?? '',
        ),
      Rest() => const RenderCell(
          letterText: '',
          lyricText: '',
          minimumColumnWidth: 2,
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

  const RenderCell.sentenceSeparator()
      : letterText = JianpuSyntax.sentenceSeparator,
        lyricText = JianpuSyntax.sentenceSeparator,
        isMeasureBar = false,
        minimumColumnWidth = 0;

  int get columnWidth => max(
        minimumColumnWidth,
        max(displayWidth(letterText), displayWidth(lyricText)),
      );
}

/// Renders a structured [Score] as plain text keyboard Jianpu.
class PlainTextRenderer {
  const PlainTextRenderer();

  String render(Score score) {
    if (score.lines.any((line) => line.segment != null)) {
      return _renderStructured(score);
    }
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
        blocks.add(_renderRow(
          [for (final cell in cells) cell.letterText],
          widths,
        ));
      }
    }
    return blocks.join('\n');
  }

  String _renderStructured(Score score) {
    final blocks = <String>[];
    var start = 0;
    while (start < score.lines.length) {
      final first = score.lines[start];
      final segment = first.segment;
      if (segment == null) {
        blocks.add(render(Score(lines: [first])));
        start += 1;
        continue;
      }

      var end = start + 1;
      while (end < score.lines.length) {
        final candidate = score.lines[end].segment;
        if (candidate == null ||
            candidate.group != segment.group ||
            candidate.row != segment.row) {
          break;
        }
        end += 1;
      }

      final rowLines = score.lines.sublist(start, end);
      final cells = <RenderCell>[];
      for (var index = 0; index < rowLines.length; index++) {
        if (index > 0) cells.add(const RenderCell.sentenceSeparator());
        cells.addAll([
          for (final token in rowLines[index].tokens)
            RenderCell.fromToken(token),
        ]);
      }
      final widths = [for (final cell in cells) cell.columnWidth];
      final hasLyrics = rowLines.any(
        (line) => line.tokens.any(_noteHasLyric),
      );
      blocks.add(_renderRow(
        [for (final cell in cells) cell.letterText],
        widths,
      ));
      if (hasLyrics) {
        blocks.add(_renderRow(
          [for (final cell in cells) cell.lyricText],
          widths,
        ));
      }
      start = end;
    }
    return blocks.join('\n');
  }

  String _renderRow(List<String> texts, List<int> widths) {
    return renderCenteredDisplayRow(texts, widths);
  }

  bool _noteHasLyric(MusicToken token) {
    return token is Note && token.lyric != null && token.lyric!.isNotEmpty;
  }
}
