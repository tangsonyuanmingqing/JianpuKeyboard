import '../models/music_token.dart';
import '../models/score.dart';
import 'plain_text_renderer.dart';
import 'display_width.dart';

/// Produces a compact image-friendly rendition without splitting a note and
/// its lyric across separate visual blocks.
class ShareImageTextRenderer {
  final int maxCellsPerRow;

  const ShareImageTextRenderer({this.maxCellsPerRow = 8});

  String render(Score score) {
    if (score.lines.any((line) => line.segment != null)) {
      return _renderStructured(score);
    }
    final blocks = <String>[];
    for (final line in score.lines) {
      final cells = [
        for (final token in line.tokens) RenderCell.fromToken(token)
      ];
      for (var start = 0; start < cells.length; start += maxCellsPerRow) {
        final end = (start + maxCellsPerRow).clamp(0, cells.length);
        final chunk = cells.sublist(start, end);
        final widths = [for (final cell in chunk) cell.columnWidth];
        final hasLyrics = line.tokens
            .sublist(start, end)
            .any((token) => token is Note && token.lyric?.isNotEmpty == true);
        blocks.add(_renderRow(
          [for (final cell in chunk) cell.letterText],
          widths,
        ));
        if (hasLyrics) {
          blocks.add(_renderRow(
            [for (final cell in chunk) cell.lyricText],
            widths,
          ));
        }
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
      blocks.addAll(_renderCellChunks(cells, rowLines));
      start = end;
    }
    return blocks.join('\n');
  }

  List<String> _renderCellChunks(
    List<RenderCell> cells,
    List<ScoreLine> sourceLines,
  ) {
    final blocks = <String>[];
    for (var start = 0; start < cells.length; start += maxCellsPerRow) {
      final end = (start + maxCellsPerRow).clamp(0, cells.length);
      final chunk = cells.sublist(start, end);
      final widths = [for (final cell in chunk) cell.columnWidth];
      final hasLyrics = sourceLines.any(
        (line) => line.tokens
            .any((token) => token is Note && token.lyric?.isNotEmpty == true),
      );
      blocks.add(_renderRow(
        [for (final cell in chunk) cell.letterText],
        widths,
      ));
      if (hasLyrics) {
        blocks.add(_renderRow(
          [for (final cell in chunk) cell.lyricText],
          widths,
        ));
      }
    }
    return blocks;
  }

  String _renderRow(List<String> texts, List<int> widths) => [
        for (var i = 0; i < texts.length; i++)
          padToDisplayWidth(texts[i], widths[i]),
      ].join(' ').trimRight();
}
