import '../../core/mapping/keyboard_mapping.dart';
import '../../core/models/conversion_result.dart';
import '../../core/models/parse_error.dart';
import '../../core/models/register.dart';
import '../../core/models/validation_message.dart';
import '../../core/renderer/display_width.dart';
import 'smart_grid_codec.dart';
import 'smart_grid_document.dart';

enum SmartGridIssueSeverity { error, warning }

class SmartGridIssue {
  final int row;
  final int column;
  final SmartGridIssueSeverity severity;
  final String message;

  const SmartGridIssue({
    required this.row,
    required this.column,
    required this.severity,
    required this.message,
  });
}

class SmartGridConversion {
  final ConversionResult result;
  final List<List<String>> outputRows;
  final List<SmartGridIssue> issues;

  const SmartGridConversion({
    required this.result,
    required this.outputRows,
    required this.issues,
  });
}

class SmartGridConverter {
  const SmartGridConverter();

  SmartGridConversion convert(
    SmartGridDocument document,
    KeyboardMapping mapping,
  ) {
    final issues = <SmartGridIssue>[];
    final outputRows = <List<String>>[];
    final errors = <ParseError>[];
    final warnings = <ValidationMessage>[];

    for (var rowIndex = 0; rowIndex < document.rows.length; rowIndex++) {
      final row = document.rows[rowIndex];
      final output = <String>[];
      for (var column = 0; column < document.columnCount; column++) {
        final value = row.cells[column];
        final validation = validateSmartGridCell(row.type, value);
        if (validation != null) {
          final issue = SmartGridIssue(
            row: rowIndex,
            column: column,
            severity: SmartGridIssueSeverity.error,
            message: validation,
          );
          issues.add(issue);
          errors.add(ParseError(
            line: rowIndex + 1,
            column: column + 1,
            tokenIndex: column + 1,
            token: value,
            message:
                '第 ${rowIndex + 1} 行 ${smartGridColumnLabel(column)} 列：$validation',
          ));
          output.add(value);
          continue;
        }
        output.add(row.type == SmartGridRowType.score
            ? _mapScoreCell(value, mapping)
            : value);
      }
      outputRows.add(List.unmodifiable(output));
    }

    final scoreByGroup = <String, int>{};
    final lyricsByGroup = <String, int>{};
    for (var index = 0; index < document.rows.length; index++) {
      final row = document.rows[index];
      if (row.cells.every((cell) => cell.isEmpty)) continue;
      if (row.type == SmartGridRowType.score) {
        scoreByGroup[row.groupId] = index;
      } else {
        lyricsByGroup[row.groupId] = index;
      }
    }
    for (final entry in scoreByGroup.entries) {
      final scoreIndex = entry.value;
      final lyricsIndex = lyricsByGroup[entry.key];
      final scoreRow = document.rows[scoreIndex];
      if (lyricsIndex == null) continue;
      final lyricRow = document.rows[lyricsIndex];
      var hasPreviousLyric = false;
      for (var column = 0; column < document.columnCount; column++) {
        final scoreCell = scoreRow.cells[column];
        final lyricCell = lyricRow.cells[column];
        final isNote = RegExp(r"^[1-7][,']?$").hasMatch(scoreCell);
        final isContinuation = lyricCell == '-';
        final hasNewLyric = lyricCell.isNotEmpty &&
            lyricCell != '|' &&
            lyricCell != '//' &&
            lyricCell != '-';
        final hasLyric = hasNewLyric || (isContinuation && hasPreviousLyric);
        if (hasNewLyric) hasPreviousLyric = true;
        if (isContinuation && !hasPreviousLyric) {
          final message =
              '第 ${lyricsIndex + 1} 行 ${smartGridColumnLabel(column)} 列的延音符号前没有歌词。';
          issues.add(SmartGridIssue(
            row: lyricsIndex,
            column: column,
            severity: SmartGridIssueSeverity.warning,
            message: message,
          ));
          warnings
              .add(ValidationMessage(line: lyricsIndex + 1, message: message));
          continue;
        }
        if (isNote && !hasLyric) {
          final message =
              '第 ${lyricsIndex + 1} 行 ${smartGridColumnLabel(column)} 列缺少歌词。';
          issues.add(SmartGridIssue(
            row: lyricsIndex,
            column: column,
            severity: SmartGridIssueSeverity.warning,
            message: message,
          ));
          warnings
              .add(ValidationMessage(line: lyricsIndex + 1, message: message));
        } else if (!isNote && hasLyric) {
          final message =
              '第 ${lyricsIndex + 1} 行 ${smartGridColumnLabel(column)} 列的歌词没有对应音符。';
          issues.add(SmartGridIssue(
            row: lyricsIndex,
            column: column,
            severity: SmartGridIssueSeverity.warning,
            message: message,
          ));
          warnings
              .add(ValidationMessage(line: lyricsIndex + 1, message: message));
        }
      }
    }

    final pairedWidths = _pairedColumnWidths(document, outputRows);
    final plainLines = <String>[];
    for (var index = 0; index < outputRows.length; index++) {
      if (document.rows[index].cells.every((cell) => cell.isEmpty)) continue;
      final row = outputRows[index];
      final last = row.lastIndexWhere((cell) => cell.isNotEmpty);
      final widths = pairedWidths[index] ??
          [
            for (var column = 0; column <= last; column++)
              displayWidth(row[column]),
          ];
      final pairedLast =
          pairedWidths.containsKey(index) ? widths.length - 1 : last;
      plainLines.add(_renderPlainRow(row, widths, pairedLast));
    }
    return SmartGridConversion(
      result: ConversionResult(
        output: plainLines.join('\n'),
        errors: List.unmodifiable(errors),
        warnings: List.unmodifiable(warnings),
      ),
      outputRows: List.unmodifiable(outputRows),
      issues: List.unmodifiable(issues),
    );
  }
}

/// Computes display-cell widths shared by non-empty score and lyrics rows in
/// the same group. A group with only one populated row stays independent.
Map<int, List<int>> _pairedColumnWidths(
  SmartGridDocument document,
  List<List<String>> outputRows,
) {
  final rowsByGroup = <String, List<int>>{};
  for (var index = 0; index < document.rows.length; index++) {
    final row = document.rows[index];
    if (row.cells.every((cell) => cell.isEmpty)) continue;
    rowsByGroup.putIfAbsent(row.groupId, () => []).add(index);
  }

  final widthsByRow = <int, List<int>>{};
  for (final indexes in rowsByGroup.values) {
    int? scoreIndex;
    int? lyricsIndex;
    for (final index in indexes) {
      final type = document.rows[index].type;
      if (type == SmartGridRowType.score && scoreIndex == null) {
        scoreIndex = index;
      } else if (type == SmartGridRowType.lyrics && lyricsIndex == null) {
        lyricsIndex = index;
      }
    }
    if (scoreIndex == null || lyricsIndex == null) continue;

    final score = outputRows[scoreIndex];
    final lyrics = outputRows[lyricsIndex];
    final last = _lastOccupiedColumn(score, lyrics);
    if (last < 0) continue;
    final widths = List<int>.generate(
      last + 1,
      (column) => displayWidth(score[column]) > displayWidth(lyrics[column])
          ? displayWidth(score[column])
          : displayWidth(lyrics[column]),
    );
    widthsByRow[scoreIndex] = widths;
    widthsByRow[lyricsIndex] = widths;
  }
  return widthsByRow;
}

int _lastOccupiedColumn(List<String> first, List<String> second) {
  for (var index = first.length - 1; index >= 0; index--) {
    if (first[index].isNotEmpty || second[index].isNotEmpty) return index;
  }
  return -1;
}

String _renderPlainRow(List<String> row, List<int> widths, int last) {
  return [
    for (var column = 0; column <= last; column++)
      padToDisplayWidth(row[column], widths[column]),
  ].join(' ').trimRight();
}

String _mapScoreCell(String value, KeyboardMapping mapping) {
  if (value.isEmpty ||
      value == '0' ||
      value == '-' ||
      value == '|' ||
      value == '//') {
    return value;
  }
  final degree = int.parse(value[0]);
  final register = value.endsWith("'")
      ? Register.high
      : value.endsWith(',')
          ? Register.low
          : Register.middle;
  return mapping.keyFor(degree, register);
}
