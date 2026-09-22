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

  String _renderRow(List<String> texts, List<int> widths) => [
        for (var i = 0; i < texts.length; i++)
          padToDisplayWidth(texts[i], widths[i]),
      ].join(' ').trimRight();
}
