import 'package:flutter_test/flutter_test.dart';
import 'package:jianpu_keyboard/core/mapping/keyboard_mapping.dart';
import 'package:jianpu_keyboard/features/converter/converter_input.dart';
import 'package:jianpu_keyboard/features/converter/smart_grid_codec.dart';
import 'package:jianpu_keyboard/features/converter/smart_grid_converter.dart';
import 'package:jianpu_keyboard/features/converter/smart_grid_document.dart';
import 'package:jianpu_keyboard/features/converter/smart_grid_inspection_renderer.dart';

void main() {
  test('column labels continue after Z', () {
    expect(smartGridColumnLabel(0), 'A');
    expect(smartGridColumnLabel(25), 'Z');
    expect(smartGridColumnLabel(26), 'AA');
    expect(smartGridColumnLabel(27), 'AB');
  });

  test('imports separate score and lyrics into paired grid rows', () {
    final imported = const SmartGridCodec().importInput(
      const ConverterInput(scoreText: '3 4 5', lyricsText: '晨 光 来'),
    );
    expect(imported.isValid, isTrue);
    expect(imported.document!.rows, hasLength(2));
    expect(imported.document!.rows[0].type, SmartGridRowType.score);
    expect(imported.document!.rows[1].type, SmartGridRowType.lyrics);
    expect(imported.document!.rows[1].cells.take(3), ['晨', '光', '来']);
    expect(
        imported.document!.rows[0].groupId, imported.document!.rows[1].groupId);
  });

  test('round trips blank alignment cells with underscore', () {
    var document = SmartGridDocument.empty(rows: 2, columns: 3);
    document = document
        .setCell(0, 0, '3')
        .setCell(0, 2, '4')
        .setCell(1, 0, '我')
        .setCell(1, 2, '你');
    final text = const SmartGridCodec().exportInput(document);
    expect(text.scoreText, contains('[谱] 3 _ 4;'));
    final imported = const SmartGridCodec().importInput(text);
    expect(imported.isValid, isTrue);
    expect(imported.document!.rows[0].cells, ['3', '', '4']);
  });

  test('converts cells without collapsing blank columns', () {
    var document = SmartGridDocument.empty(rows: 2, columns: 3);
    document = document
        .setCell(0, 0, '3')
        .setCell(0, 2, '4')
        .setCell(1, 0, '我')
        .setCell(1, 2, '你');
    final converted = const SmartGridConverter().convert(
      document,
      const KeyboardMapping(),
    );
    expect(converted.result.hasErrors, isFalse);
    expect(converted.outputRows[0], ['D', '', 'F']);
    expect(converted.outputRows[1], ['我', '', '你']);
  });

  test('inserts a cell to the right and expands without losing edge content',
      () {
    var document = SmartGridDocument.empty(rows: 2, columns: 2);
    document = document
        .setCell(0, 0, '1')
        .setCell(0, 1, '2')
        .setCell(1, 0, '我')
        .setCell(1, 1, '你');

    final result = document.applyCellOperation(
      0,
      1,
      SmartGridCellOperation.insertRowRight,
    );

    expect(result, isNotNull);
    expect(result!.columnCount, 3);
    expect(result.rows[0].cells, ['1', '', '2']);
    expect(result.rows[1].cells, ['我', '你', '']);
    expect(result.selectedRow, 0);
    expect(result.selectedColumn, 1);
  });

  test('deletes a cell by shifting only its row to the left', () {
    var document = SmartGridDocument.empty(rows: 2, columns: 3);
    document = document
        .setCell(0, 0, '1')
        .setCell(0, 1, '2')
        .setCell(0, 2, '3')
        .setCell(1, 0, '我')
        .setCell(1, 1, '你')
        .setCell(1, 2, '他');

    final result = document.applyCellOperation(
      0,
      1,
      SmartGridCellOperation.deleteRowLeft,
    );

    expect(result!.columnCount, 3);
    expect(result.rows[0].cells, ['1', '3', '']);
    expect(result.rows[1].cells, ['我', '你', '他']);
  });

  test('moves a column down through score rows only', () {
    var document = SmartGridDocument.empty(rows: 4, columns: 1);
    document = document
        .setCell(0, 0, '1')
        .setCell(1, 0, '一')
        .setCell(2, 0, '2')
        .setCell(3, 0, '二');

    final result = document.applyCellOperation(
      0,
      0,
      SmartGridCellOperation.insertSameTypeDown,
    );

    expect(result, isNotNull);
    expect(result!.rows, hasLength(5));
    expect(result.rows.map((row) => row.type), [
      SmartGridRowType.score,
      SmartGridRowType.lyrics,
      SmartGridRowType.score,
      SmartGridRowType.lyrics,
      SmartGridRowType.score,
    ]);
    expect(result.rows.map((row) => row.cells.first), ['', '一', '1', '二', '2']);
  });

  test('moves a column down through all physical rows when requested', () {
    var document = SmartGridDocument.empty(rows: 2, columns: 1);
    document = document.setCell(0, 0, '1').setCell(1, 0, '一');

    final result = document.applyCellOperation(
      0,
      0,
      SmartGridCellOperation.insertAllRowsDown,
    );

    expect(result, isNotNull);
    expect(result!.rows, hasLength(3));
    expect(result.rows.map((row) => row.cells.first), ['', '1', '一']);
    expect(result.rows.last.type, SmartGridRowType.lyrics);
  });

  test('returns null instead of dropping content at the column limit', () {
    var document = SmartGridDocument.empty(
      rows: 2,
      columns: SmartGridDocument.maxColumns,
    );
    document = document.setCell(0, SmartGridDocument.maxColumns - 1, '1');

    final result = document.applyCellOperation(
      0,
      SmartGridDocument.maxColumns - 1,
      SmartGridCellOperation.insertRowRight,
    );

    expect(result, isNull);
  });

  test('aligns paired plain-text rows by their display width', () {
    var document = SmartGridDocument.empty(rows: 2, columns: 3);
    document = document
        .setCell(0, 0, '3')
        .setCell(0, 2, '4')
        .setCell(1, 0, '黑')
        .setCell(1, 2, '你');

    final converted = const SmartGridConverter().convert(
      document,
      const KeyboardMapping(),
    );

    expect(converted.result.output, 'D   F\n黑  你');
  });

  test('aligns an English lyric cell without moving later columns', () {
    var document = SmartGridDocument.empty(rows: 2, columns: 2);
    document = document
        .setCell(0, 0, '3')
        .setCell(0, 1, '4')
        .setCell(1, 0, 'love')
        .setCell(1, 1, '你');

    final converted = const SmartGridConverter().convert(
      document,
      const KeyboardMapping(),
    );

    expect(converted.result.output, 'D    F\nlove 你');
  });

  test('keeps special symbols in their original paired columns', () {
    var document = SmartGridDocument.empty(rows: 2, columns: 6);
    document = document
        .setCell(0, 0, '3')
        .setCell(0, 1, '//')
        .setCell(0, 2, '4')
        .setCell(0, 3, '-')
        .setCell(0, 4, '|')
        .setCell(0, 5, '5')
        .setCell(1, 0, '黑')
        .setCell(1, 1, '//')
        .setCell(1, 2, '天')
        .setCell(1, 3, '-')
        .setCell(1, 4, '|')
        .setCell(1, 5, '空');

    final converted = const SmartGridConverter().convert(
      document,
      const KeyboardMapping(),
    );

    expect(converted.result.output, 'D  // F  - | G\n黑 // 天 - | 空');
  });

  test('renders an unpaired populated row independently', () {
    var document = SmartGridDocument.empty(rows: 2, columns: 2);
    document = document.setCell(1, 0, '黑').setCell(1, 1, '你');

    final converted = const SmartGridConverter().convert(
      document,
      const KeyboardMapping(),
    );

    expect(converted.result.output, '黑 你');
  });

  test('reports an exact grid coordinate for an invalid score cell', () {
    final document =
        SmartGridDocument.empty(rows: 2, columns: 3).setCell(0, 1, '1#');
    final converted = const SmartGridConverter().convert(
      document,
      const KeyboardMapping(),
    );
    expect(converted.result.hasErrors, isTrue);
    expect(converted.issues.single.row, 0);
    expect(converted.issues.single.column, 1);
    expect(converted.result.errors.single.message, contains('B 列'));
  });

  test('rejects multiple Chinese characters in one lyric cell', () {
    final document = SmartGridDocument.empty(rows: 2, columns: 1)
        .setCell(0, 0, '3')
        .setCell(1, 0, '晨光');

    final converted = const SmartGridConverter().convert(
      document,
      const KeyboardMapping(),
    );

    expect(converted.result.hasErrors, isTrue);
    expect(converted.issues.single.row, 1);
    expect(converted.issues.single.column, 0);
  });

  test('accepts a lyric continuation dash after a lyric', () {
    var document = SmartGridDocument.empty(rows: 2, columns: 2);
    document = document
        .setCell(0, 0, '3')
        .setCell(0, 1, '4')
        .setCell(1, 0, '晨')
        .setCell(1, 1, '-');

    final converted = const SmartGridConverter().convert(
      document,
      const KeyboardMapping(),
    );

    expect(converted.result.warnings, isEmpty);
  });

  test('warns when a lyric continuation dash has no previous lyric', () {
    var document = SmartGridDocument.empty(rows: 2, columns: 1);
    document = document.setCell(0, 0, '3').setCell(1, 0, '-');

    final converted = const SmartGridConverter().convert(
      document,
      const KeyboardMapping(),
    );

    expect(converted.result.warnings, hasLength(1));
    expect(converted.result.warnings.single.message, contains('延音符号前没有歌词'));
  });

  test('moves score and lyrics rows together when reordering a group', () {
    var document = SmartGridDocument.empty(rows: 4, columns: 1);
    document = document
        .setCell(0, 0, '1')
        .setCell(1, 0, '一')
        .setCell(2, 0, '2')
        .setCell(3, 0, '二');

    final reordered = document.reorderGroup(0, 4);

    expect(reordered.rows.map((row) => row.cells.first), ['2', '二', '1', '一']);
    expect(reordered.rows[2].groupId, reordered.rows[3].groupId);
  });

  test('pairs lyrics with the nearest unpaired score above', () {
    var document = SmartGridDocument.empty(rows: 4, columns: 1);
    document = document
        .setRowType(1, SmartGridRowType.score)
        .setRowType(2, SmartGridRowType.lyrics);

    expect(document.rows[1].groupId, document.rows[2].groupId);
    expect(document.rows[0].groupId, isNot(document.rows[2].groupId));
    expect(document.rows[3].groupId, isNot(document.rows[2].groupId));
  });

  test('serializes grid document as version 2', () {
    final source = SmartGridDocument.empty(rows: 2, columns: 4)
        .setCell(0, 0, '3')
        .copyWith(
          selectedRow: 1,
          selectedColumn: 3,
          horizontalOffset: 120,
          verticalOffset: 48,
        );
    final restored = SmartGridDocument.fromJson(source.toJson());
    expect(restored, isNotNull);
    expect(restored!.columnCount, 4);
    expect(restored.rows[0].cells[0], '3');
    expect(restored.selectedRow, 1);
    expect(restored.selectedColumn, 3);
    expect(restored.horizontalOffset, 120);
    expect(restored.verticalOffset, 48);
  });

  testWidgets('renders an inspection PNG with grid coordinates',
      (tester) async {
    var document = SmartGridDocument.empty(rows: 2, columns: 2);
    document = document
        .setCell(0, 0, '3')
        .setCell(0, 1, '4')
        .setCell(1, 0, '晨')
        .setCell(1, 1, '光');
    final conversion = const SmartGridConverter().convert(
      document,
      const KeyboardMapping(),
    );

    final png = await tester.runAsync(
      () => const SmartGridInspectionRenderer().render(
        document,
        conversion,
      ),
    );

    expect(png!.take(8), [137, 80, 78, 71, 13, 10, 26, 10]);
  });
}
