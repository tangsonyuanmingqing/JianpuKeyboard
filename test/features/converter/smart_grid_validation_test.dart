import 'package:flutter_test/flutter_test.dart';
import 'package:jianpu_keyboard/features/converter/smart_grid_document.dart';
import 'package:jianpu_keyboard/features/converter/smart_grid_validation.dart';

void main() {
  test('validates syntax with current row types and zero-based coordinates',
      () {
    var document = SmartGridDocument.empty(rows: 2, columns: 3)
        .setCell(0, 0, '8')
        .setCell(0, 1, "3'")
        .setCell(1, 2, ';');
    var issues = validateSmartGridDocument(document);
    expect(issues.map((issue) => (issue.row, issue.column)), [(0, 0), (1, 2)]);
    expect(
        issues.every((issue) => issue.severity == SmartGridIssueSeverity.error),
        isTrue);
    expect(issues.first.message, contains('8'));
    document = document.setRowType(0, SmartGridRowType.lyrics);
    issues = validateSmartGridDocument(document);
    expect(issues.map((issue) => (issue.row, issue.column)), [(1, 2)]);
    document = document.setCell(1, 2, '晨');
    expect(validateSmartGridDocument(document), isEmpty);
  });

  test('reports every dense error without truncating the issue list', () {
    final seed = SmartGridDocument.empty(rows: 100, columns: 100);
    final document = seed.copyWith(rows: [
      for (final row in seed.rows) row.copyWith(cells: List.filled(100, ';')),
    ]).setCell(0, 1, '4');
    final issues = validateSmartGridDocument(document);
    expect(issues.length, 9999);
    expect(issues.first.row, 0);
    expect(issues.first.column, 0);
    expect(issues.last.row, 99);
    expect(issues.last.column, 99);
    expect(issues.any((issue) => issue.row == 0 && issue.column == 1), isFalse);
  });

  test('retains Chinese, word, whitespace and special-symbol rules', () {
    for (final type in SmartGridRowType.values) {
      for (final value in ['', '|', '-', '//']) {
        expect(validateSmartGridCell(type, value), isNull);
      }
      expect(validateSmartGridCell(type, 'a b'), isNotNull);
    }
    expect(validateSmartGridCell(SmartGridRowType.lyrics, '晨光'), isNotNull);
    expect(validateSmartGridCell(SmartGridRowType.lyrics, 'morning'), isNull);
    expect(validateSmartGridCell(SmartGridRowType.score, '0'), isNull);
  });
}
