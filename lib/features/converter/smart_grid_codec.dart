import 'converter_input.dart';
import 'smart_grid_document.dart';
import 'smart_grid_lyric_tokens.dart';
import 'smart_grid_validation.dart';

export 'smart_grid_validation.dart' show validateSmartGridCell;

class SmartGridImportResult {
  final SmartGridDocument? document;
  final List<String> errors;

  const SmartGridImportResult({this.document, this.errors = const []});
  bool get isValid => document != null && errors.isEmpty;
}

class SmartGridCodec {
  const SmartGridCodec();

  SmartGridImportResult importInput(ConverterInput input) {
    final score = input.scoreText.trim();
    final lyrics = input.lyricsText.trim();
    if (score.isEmpty && lyrics.isEmpty) {
      return SmartGridImportResult(document: SmartGridDocument.empty());
    }
    final rows = score.contains('[谱]') || score.contains('[词]')
        ? _structuredRows(score)
        : _separateRows(score, lyrics);
    if (rows.isEmpty) {
      return const SmartGridImportResult(errors: ['没有可导入的谱或歌词。']);
    }
    final maxColumns = rows.fold<int>(
        1, (value, row) => row.cells.length > value ? row.cells.length : value);
    final padded = [
      for (final row in rows)
        row.copyWith(cells: [
          ...row.cells,
          ...List.filled(maxColumns - row.cells.length, '')
        ]),
    ];
    final document = SmartGridDocument(
      rows: List.unmodifiable(_pairRows(padded)),
      columnCount: maxColumns.clamp(1, SmartGridDocument.maxColumns),
    );
    final errors = <String>[];
    for (var row = 0; row < document.rows.length; row++) {
      for (var column = 0; column < document.columnCount; column++) {
        final issue = validateSmartGridCell(
            document.rows[row].type, document.rows[row].cells[column]);
        if (issue != null) {
          errors.add('第 ${row + 1} 行 ${smartGridColumnLabel(column)} 列：$issue');
        }
      }
    }
    return SmartGridImportResult(document: document, errors: errors);
  }

  ConverterInput exportInput(SmartGridDocument document) {
    final lines = <String>[];
    for (final row in document.rows) {
      if (row.cells.every((cell) => cell.isEmpty)) continue;
      final last = row.cells.lastIndexWhere((cell) => cell.isNotEmpty);
      final values = row.cells
          .take(last + 1)
          .map((cell) => cell.isEmpty ? '_' : cell)
          .join(' ');
      lines.add(
          '${row.type == SmartGridRowType.score ? '[谱]' : '[词]'} $values;');
    }
    return ConverterInput(scoreText: lines.join('\n'));
  }
}

List<SmartGridRow> _separateRows(String score, String lyrics) {
  final scoreLines = _logicalLines(score);
  final lyricLines = _logicalLines(lyrics);
  final rows = <SmartGridRow>[];
  final count = scoreLines.length > lyricLines.length
      ? scoreLines.length
      : lyricLines.length;
  for (var index = 0; index < count; index++) {
    final group = 'group-${index + 1}';
    if (index < scoreLines.length) {
      rows.add(_row(
          'score-$index', group, SmartGridRowType.score, scoreLines[index]));
    }
    if (index < lyricLines.length) {
      rows.add(_row(
          'lyrics-$index', group, SmartGridRowType.lyrics, lyricLines[index],
          splitChinese: true));
    }
  }
  return rows;
}

List<SmartGridRow> _structuredRows(String text) {
  final rows = <SmartGridRow>[];
  SmartGridRowType? active;
  var serial = 0;
  for (final rawLine
      in text.replaceAll('\r\n', '\n').replaceAll('\r', '\n').split('\n')) {
    var line = rawLine.trim();
    if (line.isEmpty) continue;
    if (line.startsWith('[谱]')) {
      active = SmartGridRowType.score;
      line = line.substring(3).trim();
    } else if (line.startsWith('[词]')) {
      active = SmartGridRowType.lyrics;
      line = line.substring(3).trim();
    }
    if (active == null || line.isEmpty) continue;
    for (final part in line.split(';')) {
      if (part.trim().isEmpty) continue;
      rows.add(_row('import-${serial++}', 'group-$serial', active, part,
          splitChinese: active == SmartGridRowType.lyrics));
    }
  }
  return rows;
}

List<String> _logicalLines(String value) => value
    .replaceAll('\r\n', '\n')
    .replaceAll('\r', '\n')
    .split(RegExp(r'[;\n]'))
    .map((line) => line.trim())
    .where((line) => line.isNotEmpty)
    .toList();

SmartGridRow _row(String id, String group, SmartGridRowType type, String text,
    {bool splitChinese = false}) {
  final cells = _tokens(text, splitChinese: splitChinese);
  return SmartGridRow(
      id: id,
      groupId: group,
      type: type,
      cells: cells.isEmpty ? const [''] : cells);
}

List<String> _tokens(String text, {required bool splitChinese}) {
  if (splitChinese) {
    return splitSmartGridLyricCells(text)
        .map((value) => value == '_' ? '' : value)
        .toList();
  }
  final normalized =
      text.replaceAll('//', ' // ').replaceAll('|', ' | ').trim();
  final chunks =
      normalized.split(RegExp(r'[\t ]+')).where((item) => item.isNotEmpty);
  final result = <String>[];
  for (final chunk in chunks) {
    if (chunk == '_') {
      result.add('');
      continue;
    }
    result.add(chunk);
  }
  return result;
}

List<SmartGridRow> _pairRows(List<SmartGridRow> rows) {
  String? pending;
  var group = 0;
  final result = <SmartGridRow>[];
  for (final row in rows) {
    if (row.type == SmartGridRowType.score) {
      pending = 'group-${++group}';
      result.add(row.copyWith(groupId: pending));
    } else {
      result.add(row.copyWith(groupId: pending ?? 'group-${++group}'));
      pending = null;
    }
  }
  return result;
}
