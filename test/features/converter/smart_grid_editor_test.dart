import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jianpu_keyboard/features/converter/smart_grid_document.dart';
import 'package:jianpu_keyboard/features/converter/smart_grid_editor.dart';

void main() {
  testWidgets('pastes a tab and newline matrix and expands columns',
      (tester) async {
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.getData') {
          return <String, dynamic>{'text': '3\t4\t5\n晨\t光\t来'};
        }
        return null;
      },
    );
    var document = SmartGridDocument.empty(rows: 2, columns: 2);

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: StatefulBuilder(builder: (context, setState) {
          return SmartGridEditor(
            document: document,
            onChanged: (next) => setState(() => document = next),
          );
        }),
      ),
    ));

    await tester.tap(find.byKey(const ValueKey('grid-cell-row-1:0')));
    await tester.tap(find.byKey(const Key('grid-paste')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(document.columnCount, 3);
    expect(document.rows[0].cells, ['3', '4', '5']);
    expect(document.rows[1].cells, ['晨', '光', '来']);
  });

  testWidgets('reports selected cell coordinates for draft restoration',
      (tester) async {
    final document = SmartGridDocument.empty(rows: 2, columns: 3);
    SmartGridDocument? viewState;

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SmartGridEditor(
          document: document,
          onChanged: (_) {},
          onViewStateChanged: (next) => viewState = next,
        ),
      ),
    ));
    await tester.tap(find.byKey(const ValueKey('grid-cell-row-2:2')));

    expect(viewState?.selectedRow, 1);
    expect(viewState?.selectedColumn, 2);
  });

  testWidgets('runs a cell operation from the toolbar and undoes it',
      (tester) async {
    var document = SmartGridDocument.empty(rows: 2, columns: 2)
        .setCell(0, 0, '1')
        .setCell(0, 1, '2');

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: StatefulBuilder(builder: (context, setState) {
          return SmartGridEditor(
            document: document,
            onChanged: (next) => setState(() => document = next),
          );
        }),
      ),
    ));

    await tester.tap(find.byKey(const ValueKey('grid-cell-row-1:0')));
    await tester.tap(find.byKey(const Key('grid-cell-actions')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('插入空格，本行向右移动'));
    await tester.pumpAndSettle();

    expect(document.columnCount, 3);
    expect(document.rows[0].cells, ['', '1', '2']);

    await tester.tap(find.byTooltip('撤销'));
    await tester.pumpAndSettle();
    expect(document.columnCount, 2);
    expect(document.rows[0].cells, ['1', '2']);
  });

  testWidgets('confirms before moving a note into a lyrics row',
      (tester) async {
    var document = SmartGridDocument.empty(rows: 2, columns: 1)
        .setCell(0, 0, '1')
        .setCell(1, 0, '一');

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: StatefulBuilder(builder: (context, setState) {
          return SmartGridEditor(
            document: document,
            onChanged: (next) => setState(() => document = next),
          );
        }),
      ),
    ));

    await tester.tap(find.byKey(const ValueKey('grid-cell-row-1:0')));
    await tester.tap(find.byKey(const Key('grid-cell-actions')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('插入空格，本列所有行向下移动'));
    await tester.pumpAndSettle();

    expect(find.text('内容可能进入不匹配的行'), findsOneWidget);
    await tester.tap(find.text('继续移动'));
    await tester.pumpAndSettle();
    expect(document.rows.map((row) => row.cells.first), ['', '1', '一']);
  });

  testWidgets('opens the same cell operation menu by long pressing a cell',
      (tester) async {
    final document = SmartGridDocument.empty(rows: 2, columns: 1);

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SmartGridEditor(document: document, onChanged: (_) {}),
      ),
    ));

    await tester.longPress(find.byKey(const ValueKey('grid-cell-row-1:0')));
    await tester.pumpAndSettle();

    expect(find.text('插入空格，本行向右移动'), findsOneWidget);
  });
}
