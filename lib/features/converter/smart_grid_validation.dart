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

/// Editing-time cell syntax checks, not conversion or lyric alignment.
List<SmartGridIssue> validateSmartGridDocument(SmartGridDocument document) => [
      for (var row = 0; row < document.rows.length; row++)
        for (var column = 0; column < document.columnCount; column++)
          if (validateSmartGridCell(
                  document.rows[row].type, document.rows[row].cells[column])
              case final String message)
            SmartGridIssue(
              row: row,
              column: column,
              severity: SmartGridIssueSeverity.error,
              message: message,
            ),
    ];

String? validateSmartGridCell(SmartGridRowType type, String value) {
  if (value.isEmpty || value == '//' || value == '|' || value == '-') {
    return null;
  }
  if (value == ';') return '表格中换行由行决定，不能输入英文分号。';
  if (value.contains(RegExp(r'\s'))) return '一个格子只能填写一个汉字、单词或符号。';
  if (type == SmartGridRowType.lyrics &&
      value.contains(RegExp(r'[\u3400-\u9fff]')) &&
      value.runes.length != 1) {
    return '一个歌词格只能填写一个汉字；多个汉字请分到相邻格子。';
  }
  if (type == SmartGridRowType.score &&
      !RegExp(r"^(?:[1-7][,']?|0)$").hasMatch(value)) {
    return '无法识别的数字简谱符号“$value”。';
  }
  return null;
}
