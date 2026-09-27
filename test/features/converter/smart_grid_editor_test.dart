import 'dart:collection';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jianpu_keyboard/app/theme/app_typography.dart';
import 'package:jianpu_keyboard/core/mapping/keyboard_mapping.dart';
import 'package:jianpu_keyboard/features/converter/resizable_panel.dart';
import 'package:jianpu_keyboard/features/converter/smart_grid_converter.dart';
import 'package:jianpu_keyboard/features/converter/smart_grid_document.dart';
import 'package:jianpu_keyboard/features/converter/smart_grid_editor.dart';
import 'package:jianpu_keyboard/features/converter/smart_grid_text_field.dart';
import 'package:jianpu_keyboard/features/converter/smart_grid_issue_overlay.dart';
import 'package:jianpu_keyboard/features/converter/table_scale.dart';

Future<void> _rightClick(WidgetTester tester, Finder target) async {
  final gesture = await tester.startGesture(
    tester.getCenter(target),
    kind: PointerDeviceKind.mouse,
    buttons: kSecondaryButton,
  );
  await gesture.up();
  await tester.pumpAndSettle();
}

Future<void> _doubleClick(WidgetTester tester, Finder target) async {
  final position = tester.getCenter(target);
  for (var click = 0; click < 2; click++) {
    final gesture = await tester.startGesture(
      position,
      kind: PointerDeviceKind.mouse,
    );
    await gesture.up();
    await tester.pump(const Duration(milliseconds: 10));
  }
}

Future<void> _expectVerticalControllersStaySynchronized(
  WidgetTester tester,
  ScrollController first,
  ScrollController second,
) async {
  first.jumpTo(120);
  await tester.pump();
  expect(second.offset, closeTo(120, .5));

  second.jumpTo(220);
  await tester.pump();
  expect(first.offset, closeTo(220, .5));

  first.jumpTo(first.position.maxScrollExtent + 100);
  await tester.pump();
  expect(second.offset, closeTo(second.position.maxScrollExtent, .5));
}

void main() {
  testWidgets('issue overlay transitions keep the active editor and focus',
      (tester) async {
    final document = SmartGridDocument.empty(rows: 2, columns: 3);
    var issues = <SmartGridIssue>[];
    late VoidCallback rebuild;
    await tester.pumpWidget(MaterialApp(home: Scaffold(
      body: StatefulBuilder(builder: (context, setState) {
        rebuild = () => setState(() {});
        return SmartGridEditor(
            document: document, issues: issues, onChanged: (_) {});
      }),
    )));
    final cell = find.byKey(const ValueKey('grid-cell-row-1:1'));
    await tester.tap(cell);
    await tester.pump();
    final editable =
        find.descendant(of: cell, matching: find.byType(EditableText));
    final initial = tester.state(editable);
    final focus = tester.widget<EditableText>(editable).focusNode;
    expect(focus.hasFocus, isTrue);
    for (final next in [
      [
        const SmartGridIssue(
            row: 0,
            column: 1,
            severity: SmartGridIssueSeverity.error,
            message: 'error')
      ],
      <SmartGridIssue>[],
    ]) {
      issues = next;
      rebuild();
      await tester.pump();
      expect(identical(tester.state(editable), initial), isTrue);
      expect(focus.hasFocus, isTrue);
    }
  });
  testWidgets('row geometry tracks scale and reaches the final row',
      (tester) async {
    final document = SmartGridDocument.empty(rows: 100, columns: 3);
    var scale = const TableScale(0);
    late VoidCallback rebuild;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: StatefulBuilder(builder: (context, setState) {
          rebuild = () => setState(() {});
          return SmartGridEditor(
            document: document,
            scale: scale,
            panelSize: const ResizablePanelSize(width: 400, height: 250),
            onChanged: (_) {},
          );
        }),
      ),
    ));
    for (final percent in [0, 50, 100]) {
      scale = TableScale(percent);
      rebuild();
      await tester.pump();
      final lists = tester
          .widgetList<ReorderableListView>(find.byType(ReorderableListView))
          .toList();
      // Lazy lists refine their scroll estimate after changing the scale.
      for (var attempt = 0; attempt < 5; attempt++) {
        lists.first.scrollController!
            .jumpTo(lists.first.scrollController!.position.maxScrollExtent);
        await tester.pump();
      }
      expect(find.byKey(const ValueKey('grid-cell-row-100:0')), findsOneWidget);
      expect(lists.last.scrollController!.offset,
          closeTo(lists.first.scrollController!.offset, .5));
    }
  });

  testWidgets('drags paired rows with viewport-only fixed-height lists',
      (tester) async {
    var document = SmartGridDocument.empty(rows: 6, columns: 3);
    final ids = document.rows.map((row) => row.id).toSet();
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: StatefulBuilder(
            builder: (context, setState) => SmartGridEditor(
                  document: document,
                  panelSize: const ResizablePanelSize(width: 500, height: 400),
                  onChanged: (next) => setState(() => document = next),
                )),
      ),
    ));
    await tester.drag(
        find.byKey(const ValueKey('grid-row-header-0')), const Offset(0, 180));
    await tester.pumpAndSettle();
    expect(document.rows.first.id, isNot('row-1'));
    expect(document.rows.map((row) => row.id).toSet(), ids);
    final moved = document.rows.indexWhere((row) => row.id == 'row-1');
    expect(document.rows[moved + 1].id, 'row-2');
    expect(document.rows[moved].groupId, document.rows[moved + 1].groupId);
    expect(tester.takeException(), isNull);
  });
  testWidgets('bounds mounted editors to viewport rows during scrolling',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SmartGridEditor(
          document: SmartGridDocument.empty(rows: 100, columns: 100),
          panelSize: const ResizablePanelSize(width: 400, height: 250),
          onChanged: (_) {},
        ),
      ),
    ));
    void expectBoundedRows() {
      final rows = tester
          .widgetList<SmartGridTextField>(
              find.byType(SmartGridTextField, skipOffstage: false))
          .map((field) {
        final key = (field.key! as ValueKey<String>).value;
        return key.split(':').first;
      }).toSet();
      // 221.5px viewport / 43.5px cell: at most 7 partially visible rows.
      expect(rows.length, lessThanOrEqualTo(7));
    }

    expectBoundedRows();
    final body = tester
        .widgetList<ReorderableListView>(find.byType(ReorderableListView))
        .first
        .scrollController!;
    body.jumpTo(180);
    await tester.pump();
    expectBoundedRows();
    final horizontal = tester
        .widget<SingleChildScrollView>(find.byType(SingleChildScrollView))
        .controller!;
    horizontal.jumpTo(180);
    await tester.pump();
    expectBoundedRows();
  });
  testWidgets('does not rescan dense issues per cell during horizontal scroll',
      (tester) async {
    final issues = _CountingIssues([
      for (var row = 0; row < 100; row++)
        for (var column = 0; column < 100; column++)
          SmartGridIssue(
            row: row,
            column: column,
            severity: SmartGridIssueSeverity.error,
            message: '$row:$column',
          ),
    ]);
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SmartGridEditor(
          document: SmartGridDocument.empty(rows: 100, columns: 100),
          issues: issues,
          panelSize: const ResizablePanelSize(width: 400, height: 250),
          onChanged: (_) {},
        ),
      ),
    ));
    expect(issues.reads, lessThanOrEqualTo(issues.length),
        reason: 'Index each issue once, not once per rendered cell.');
    issues.reads = 0;
    final horizontal = tester
        .widget<SingleChildScrollView>(find.byType(SingleChildScrollView))
        .controller!;
    horizontal.jumpTo(180);
    await tester.pump();
    expect(issues.reads, 0,
        reason: 'Scrolling an unchanged issue set must reuse its index.');
    expect(
        tester
            .widgetList<SmartGridIssueOverlay>(
                find.byType(SmartGridIssueOverlay))
            .any((row) => row.issues.isNotEmpty),
        isTrue);
  });
  testWidgets('undoes an auto-advancing multi-cell lyric edit in one step',
      (tester) async {
    var document =
        SmartGridDocument.empty(rows: 2, columns: 3).setCell(1, 1, '旧');
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: StatefulBuilder(
            builder: (context, setState) => SmartGridEditor(
                  document: document,
                  onChanged: (next) => setState(() => document = next),
                )),
      ),
    ));
    final cell = find.byKey(const ValueKey('grid-cell-row-2:0'));
    await tester.tap(cell);
    await tester.pump();
    await tester.enterText(cell, '晨光');
    await tester.pumpAndSettle();
    expect(document.rows[1].cells.take(2), ['晨', '光']);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyZ);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pumpAndSettle();
    expect(document.rows[1].cells, ['', '旧', '']);
    expect(document.selectedRow, 1);
    expect(document.selectedColumn, 0);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyY);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pumpAndSettle();
    expect(document.rows[1].cells.take(2), ['晨', '光']);
  });

  testWidgets('releases inactive offscreen editors and restores their values',
      (tester) async {
    final document =
        SmartGridDocument.empty(rows: 2, columns: 100).setCell(0, 1, '7');
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SmartGridEditor(
          document: document,
          panelSize: const ResizablePanelSize(width: 500, height: 250),
          onChanged: (_) {},
        ),
      ),
    ));
    final cell = find.byKey(const ValueKey('grid-cell-row-1:1'));
    final initialController =
        tester.widget<SmartGridTextField>(cell).controller;
    final horizontal = tester
        .widget<SingleChildScrollView>(find.byType(SingleChildScrollView))
        .controller!;
    horizontal.jumpTo(horizontal.position.maxScrollExtent);
    await tester.pump();
    expect(cell, findsNothing);
    horizontal.jumpTo(0);
    await tester.pump();
    final restoredController =
        tester.widget<SmartGridTextField>(cell).controller;
    expect(identical(initialController, restoredController), isFalse);
    expect(restoredController.text, '7');
    await tester.pumpWidget(const SizedBox.shrink());
    expect(tester.takeException(), isNull);
  });

  testWidgets('invalidates cached cells when issues or scale change',
      (tester) async {
    final document = SmartGridDocument.empty(rows: 2, columns: 3);
    var scale = const TableScale(0);
    var issues = <SmartGridIssue>[];
    late VoidCallback rebuild;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: StatefulBuilder(builder: (context, setState) {
          rebuild = () => setState(() {});
          return SmartGridEditor(
            document: document,
            scale: scale,
            issues: issues,
            onChanged: (_) {},
          );
        }),
      ),
    ));
    final cell = find.byKey(const ValueKey('grid-cell-row-1:1'));
    final smallFont = tester.widget<SmartGridTextField>(cell).style.fontSize!;
    scale = const TableScale(100);
    issues = [
      const SmartGridIssue(
        row: 0,
        column: 1,
        severity: SmartGridIssueSeverity.error,
        message: '错误',
      ),
    ];
    rebuild();
    await tester.pump();
    expect(tester.widget<SmartGridTextField>(cell).style.fontSize,
        greaterThan(smallFont));
    expect(
        tester
            .widgetList<SmartGridIssueOverlay>(
                find.byType(SmartGridIssueOverlay))
            .expand((row) => row.issues),
        hasLength(1));
    issues = [];
    rebuild();
    await tester.pump();
    expect(
        tester
            .widgetList<SmartGridIssueOverlay>(
                find.byType(SmartGridIssueOverlay))
            .expand((row) => row.issues),
        isEmpty);
  });

  testWidgets('preserves an active IME composition through viewport updates',
      (tester) async {
    var document = SmartGridDocument.empty(rows: 2, columns: 100);
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: StatefulBuilder(
            builder: (context, setState) => SmartGridEditor(
                  document: document,
                  panelSize: const ResizablePanelSize(width: 500, height: 250),
                  onChanged: (next) => setState(() => document = next),
                  onViewStateChanged: (next) => setState(() => document = next),
                )),
      ),
    ));
    final cell = find.byKey(const ValueKey('grid-cell-row-2:0'));
    await tester.tap(cell);
    await tester.pump();
    await tester.showKeyboard(cell);
    final controller = tester.widget<SmartGridTextField>(cell).controller;
    tester.testTextInput.updateEditingValue(const TextEditingValue(
      text: '晨光',
      selection: TextSelection.collapsed(offset: 2),
      composing: TextRange(start: 0, end: 2),
    ));
    await tester.pump();
    final horizontal = tester
        .widget<SingleChildScrollView>(find.byType(SingleChildScrollView))
        .controller!;
    horizontal.jumpTo(horizontal.position.maxScrollExtent);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(controller.text, '晨光');
    expect(controller.value.composing, const TextRange(start: 0, end: 2));
    tester.testTextInput.updateEditingValue(const TextEditingValue(
      text: '晨光',
      selection: TextSelection.collapsed(offset: 2),
    ));
    await tester.pumpAndSettle();
    expect(document.rows[1].cells.take(2), ['晨', '光']);
  });

  testWidgets('reveals and focuses a cell outside both viewport axes',
      (tester) async {
    var document = SmartGridDocument.empty(rows: 40, columns: 100);
    final editorKey = GlobalKey<SmartGridEditorState>();
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: StatefulBuilder(
            builder: (context, setState) => SmartGridEditor(
                  key: editorKey,
                  document: document,
                  panelSize: const ResizablePanelSize(width: 500, height: 250),
                  onChanged: (next) => setState(() => document = next),
                  onViewStateChanged: (next) => setState(() => document = next),
                )),
      ),
    ));
    editorKey.currentState!.focusCell(22, 80);
    await tester.pumpAndSettle();
    final cell = find.byKey(const ValueKey('grid-cell-row-23:80'));
    expect(cell.hitTestable(), findsOneWidget);
    expect(tester.widget<SmartGridTextField>(cell).focusNode.hasFocus, isTrue);
    await tester.enterText(cell, '7');
    await tester.pump();
    expect(document.rows[22].cells[80], '7');
  });

  testWidgets(
      'keeps controller edits attached to row identity after reordering',
      (tester) async {
    var document = SmartGridDocument.empty(rows: 4, columns: 3);
    late void Function(SmartGridDocument) replace;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: StatefulBuilder(builder: (context, setState) {
          replace = (next) => setState(() => document = next);
          return SmartGridEditor(document: document, onChanged: replace);
        }),
      ),
    ));
    final cell = find.byKey(const ValueKey('grid-cell-row-1:0'));
    await tester.enterText(cell, '3');
    await tester.pump();
    replace(document.reorderGroup(0, 4));
    await tester.pumpAndSettle();
    await tester.enterText(cell, '7');
    await tester.pump();
    expect(document.rows.singleWhere((row) => row.id == 'row-1').cells[0], '7');
    expect(document.rows.singleWhere((row) => row.id == 'row-3').cells[0], '');
  });

  testWidgets('updates selection on rapid alternating cell clicks',
      (tester) async {
    var document = SmartGridDocument.empty(rows: 2, columns: 3);
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: StatefulBuilder(
            builder: (context, setState) => SmartGridEditor(
                  document: document,
                  onChanged: (next) => setState(() => document = next),
                  onViewStateChanged: (next) => setState(() => document = next),
                )),
      ),
    ));
    for (final column in [1, 2, 1, 2, 1, 2]) {
      await tester.tap(find.byKey(ValueKey('grid-cell-row-1:$column')));
      await tester.pump(const Duration(milliseconds: 10));
      expect(document.selectedColumn, column);
    }
  });

  testWidgets('mounts only viewport columns and reaches the last column',
      (tester) async {
    final document = SmartGridDocument.empty(rows: 8, columns: 100);
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SmartGridEditor(
          document: document,
          panelSize: const ResizablePanelSize(width: 500, height: 250),
          onChanged: (_) {},
        ),
      ),
    ));
    expect(find.byType(SmartGridTextField).evaluate().length, lessThan(150));
    final horizontal = tester
        .widget<SingleChildScrollView>(find.byType(SingleChildScrollView))
        .controller!;
    horizontal.jumpTo(horizontal.position.maxScrollExtent);
    await tester.pump();
    expect(find.byKey(const ValueKey('grid-cell-row-1:99')), findsOneWidget);
    expect(find.byType(SmartGridTextField).evaluate().length, lessThan(150));
  });

  testWidgets('reuses untouched cell subtrees on selection and content changes',
      (tester) async {
    var document = SmartGridDocument.empty(rows: 2, columns: 8);
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: StatefulBuilder(
            builder: (context, setState) => SmartGridEditor(
                  document: document,
                  onChanged: (next) => setState(() => document = next),
                  onViewStateChanged: (next) => setState(() => document = next),
                )),
      ),
    ));
    final untouched = find.byKey(const ValueKey('grid-cell-row-1:4'));
    final before = tester.widget<SmartGridTextField>(untouched);
    final edited = find.byKey(const ValueKey('grid-cell-row-1:1'));
    await tester.tap(edited);
    await tester.pump();
    expect(identical(tester.widget<SmartGridTextField>(untouched), before),
        isTrue);
    await tester.enterText(edited, '3');
    await tester.pump();
    expect(document.rows.first.cells[1], '3');
    expect(identical(tester.widget<SmartGridTextField>(untouched), before),
        isTrue);
  });

  testWidgets('uses the UI font for smart-grid cells', (tester) async {
    final document = SmartGridDocument.empty(rows: 2, columns: 2);

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SmartGridEditor(document: document, onChanged: (_) {}),
      ),
    ));

    final cell = tester.widget<EditableText>(
      find.descendant(
        of: find.byKey(const ValueKey('grid-cell-row-1:0')),
        matching: find.byType(EditableText),
      ),
    );
    expect(cell.style.fontFamily, AppTypography.uiFamily);
    expect(cell.style.fontWeight, FontWeight.w400);
  });

  testWidgets(
      'double clicking a score cell opens the note picker and moves right',
      (tester) async {
    var document = SmartGridDocument.empty(rows: 2, columns: 2);
    (int, int)? selection;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: StatefulBuilder(builder: (context, setState) {
          return SmartGridEditor(
            document: document,
            onChanged: (next) => setState(() => document = next),
            onSelectionChanged: (value) => selection = value,
          );
        }),
      ),
    ));

    final cell = find.byKey(const ValueKey('grid-cell-row-1:1'));
    await _doubleClick(tester, cell);
    await tester.pumpAndSettle();
    expect(find.text('选择数字简谱'), findsOneWidget);

    await tester.tap(find.byKey(const Key('score-picker-number-3')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('score-picker-register-high')));
    await tester.pumpAndSettle();

    expect(document.rows[0].cells[1], "3'");
    expect(document.columnCount, 3);
    expect(selection, (0, 2));
    expect(document.selectedRow, 0);
    expect(document.selectedColumn, 2);
    final activeCell = tester.widget<EditableText>(
      find.descendant(
        of: find.byKey(const ValueKey('grid-cell-row-1:2')),
        matching: find.byType(EditableText),
      ),
    );
    expect(activeCell.focusNode.hasFocus, isTrue);
  });

  testWidgets(
      'restores the horizontal scrollbar after closing the score picker',
      (tester) async {
    var document = SmartGridDocument.empty(rows: 2, columns: 20);
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: StatefulBuilder(builder: (context, setState) {
          return SmartGridEditor(
            document: document,
            panelSize: const ResizablePanelSize(width: 500, height: 250),
            onChanged: (next) => setState(() => document = next),
          );
        }),
      ),
    ));
    await tester.pump();

    final panel = find.byKey(const Key('resizable-panel-smart-grid'));
    final origin = tester.getTopLeft(panel);
    final size = tester.getSize(panel);
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(
      location: origin + Offset(size.width / 2, size.height - 4),
    );
    await tester.pump();
    expect(
      tester.widget<Scrollbar>(find.byType(Scrollbar).first).thumbVisibility,
      isTrue,
    );

    await mouse.moveTo(origin + Offset(size.width / 2, size.height / 2));
    await tester.pump(const Duration(milliseconds: 800));
    expect(
      tester.widget<Scrollbar>(find.byType(Scrollbar).first).thumbVisibility,
      isFalse,
    );

    final cell = find.byKey(const ValueKey('grid-cell-row-1:0'));
    await _doubleClick(tester, cell);
    await tester.pumpAndSettle();
    expect(find.text('选择数字简谱'), findsOneWidget);
    await tester.tap(find.byKey(const Key('score-picker-rest')));
    await tester.pumpAndSettle();

    await mouse.moveTo(
      tester.getTopLeft(panel) + Offset(size.width / 2, size.height - 4),
    );
    await tester.pump();
    expect(
      tester.widget<Scrollbar>(find.byType(Scrollbar).first).thumbVisibility,
      isTrue,
    );
  });

  testWidgets('keeps the output horizontal scrollbar visible through a rebuild',
      (tester) async {
    final document = SmartGridDocument.empty(rows: 2, columns: 20);
    final conversion = const SmartGridConverter().convert(
      document,
      const KeyboardMapping(),
    );

    Widget buildOutput(TableScale scale) => MaterialApp(
          home: Scaffold(
            body: SmartGridOutputView(
              document: document,
              conversion: conversion,
              panelSize: const ResizablePanelSize(width: 500, height: 250),
              scale: scale,
            ),
          ),
        );

    await tester.pumpWidget(buildOutput(const TableScale(50)));
    await tester.pump();
    final panel = find.byKey(const Key('resizable-panel-letter-grid'));
    final origin = tester.getTopLeft(panel);
    final size = tester.getSize(panel);
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(
      location: origin + Offset(size.width / 2, size.height - 4),
    );
    await tester.pump();
    expect(
      tester.widget<Scrollbar>(find.byType(Scrollbar).first).thumbVisibility,
      isTrue,
    );

    await tester.pumpWidget(buildOutput(const TableScale(51)));
    await tester.pump();
    expect(
      tester.widget<Scrollbar>(find.byType(Scrollbar).first).thumbVisibility,
      isTrue,
    );
  });

  testWidgets('synchronizes both editor vertical panes in both directions',
      (tester) async {
    final document = SmartGridDocument.empty(rows: 40, columns: 2);
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SmartGridEditor(
          document: document,
          panelSize: const ResizablePanelSize(width: 500, height: 250),
          onChanged: (_) {},
        ),
      ),
    ));
    await tester.pump();

    final lists = tester
        .widgetList<ReorderableListView>(find.byType(ReorderableListView))
        .toList();
    expect(lists, hasLength(2));
    final body = lists.first.scrollController!;
    final frozen = lists.last.scrollController!;

    await _expectVerticalControllersStaySynchronized(tester, body, frozen);

    await tester.pumpWidget(const SizedBox.shrink());
    expect(tester.takeException(), isNull);
  });

  testWidgets('synchronizes both output vertical panes in both directions',
      (tester) async {
    final document = SmartGridDocument.empty(rows: 40, columns: 2);
    final conversion = const SmartGridConverter().convert(
      document,
      const KeyboardMapping(),
    );
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SmartGridOutputView(
          document: document,
          conversion: conversion,
          panelSize: const ResizablePanelSize(width: 500, height: 250),
        ),
      ),
    ));
    await tester.pump();

    final lists = tester.widgetList<ListView>(find.byType(ListView)).toList();
    expect(lists, hasLength(2));
    final body = lists.first.controller!;
    final frozen = lists.last.controller!;

    await _expectVerticalControllersStaySynchronized(tester, frozen, body);

    await tester.pumpWidget(const SizedBox.shrink());
    expect(tester.takeException(), isNull);
  });

  testWidgets('score picker clears a cell without moving selection',
      (tester) async {
    var document =
        SmartGridDocument.empty(rows: 2, columns: 2).setCell(0, 0, '4');
    (int, int)? selection;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: StatefulBuilder(builder: (context, setState) {
          return SmartGridEditor(
            document: document,
            onChanged: (next) => setState(() => document = next),
            onSelectionChanged: (value) => selection = value,
          );
        }),
      ),
    ));

    final cell = find.byKey(const ValueKey('grid-cell-row-1:0'));
    await tester.tap(cell);
    await tester.tap(cell);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('score-picker-clear')));
    await tester.pumpAndSettle();

    expect(document.rows[0].cells[0], isEmpty);
    expect(selection, (0, 0));
  });

  testWidgets('spreads mixed lyric input across adjacent cells',
      (tester) async {
    var document =
        SmartGridDocument.empty(rows: 2, columns: 2).setCell(1, 1, '旧');
    (int, int)? selection;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: StatefulBuilder(builder: (context, setState) {
          return SmartGridEditor(
            document: document,
            onChanged: (next) => setState(() => document = next),
            onSelectionChanged: (value) => selection = value,
          );
        }),
      ),
    ));

    final cell = find.byKey(const ValueKey('grid-cell-row-2:0'));
    await tester.tap(cell);
    await tester.enterText(cell, '第520次');
    await tester.pumpAndSettle();

    expect(document.rows[1].cells, ['第', '520', '次', '']);
    expect(selection, (1, 3));
    expect(document.selectedRow, 1);
    expect(document.selectedColumn, 3);
    final activeCell = tester.widget<EditableText>(
      find.descendant(
        of: find.byKey(const ValueKey('grid-cell-row-2:3')),
        matching: find.byType(EditableText),
      ),
    );
    expect(activeCell.focusNode.hasFocus, isTrue);
  });

  testWidgets('retains a typed numeric lyric in one cell until navigation',
      (tester) async {
    var document = SmartGridDocument.empty(rows: 2, columns: 3);
    (int, int)? selection;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: StatefulBuilder(builder: (context, setState) {
          return SmartGridEditor(
            document: document,
            onChanged: (next) => setState(() => document = next),
            onSelectionChanged: (value) => selection = value,
          );
        }),
      ),
    ));

    final cell = find.byKey(const ValueKey('grid-cell-row-2:0'));
    await tester.tap(cell);
    await tester.enterText(cell, '520');
    await tester.pump();

    expect(document.rows[1].cells[0], '520');
    expect(selection, (1, 0));
  });

  testWidgets(
      'spreads a committed IME value even when only composition changes',
      (tester) async {
    var document = SmartGridDocument.empty(rows: 2, columns: 3);
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

    final cell = find.byKey(const ValueKey('grid-cell-row-2:0'));
    await tester.tap(cell);
    tester.testTextInput.updateEditingValue(
      const TextEditingValue(
        text: '晨光',
        selection: TextSelection.collapsed(offset: 2),
        composing: TextRange(start: 0, end: 2),
      ),
    );
    await tester.pump();
    expect(document.rows[1].cells.first, isEmpty);

    tester.testTextInput.updateEditingValue(
      const TextEditingValue(
        text: '晨光',
        selection: TextSelection.collapsed(offset: 2),
      ),
    );
    await tester.pumpAndSettle();
    expect(document.rows[1].cells.take(2), ['晨', '光']);
  });

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

  testWidgets('opens a cell context menu on one secondary click',
      (tester) async {
    var document = SmartGridDocument.empty(rows: 2, columns: 2)
        .setCell(1, 0, '1')
        .setCell(1, 1, '2');
    (int, int)? selection;

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: StatefulBuilder(builder: (context, setState) {
          return SmartGridEditor(
            document: document,
            onChanged: (next) => setState(() => document = next),
            onSelectionChanged: (next) => selection = next,
          );
        }),
      ),
    ));

    await _rightClick(
      tester,
      find.byKey(const ValueKey('grid-cell-row-2:0')),
    );

    expect(selection, (1, 0));
    expect(find.text('插入空格，本行向右移动'), findsOneWidget);
    await tester.tap(find.text('插入空格，本行向右移动'));
    await tester.pumpAndSettle();
    expect(document.columnCount, 3);
    expect(document.rows[1].cells, ['', '1', '2']);
  });

  testWidgets(
      'does not open a duplicate menu while the secondary button is held',
      (tester) async {
    final document = SmartGridDocument.empty(rows: 1, columns: 1);

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SmartGridEditor(document: document, onChanged: (_) {}),
      ),
    ));

    final target = find.byKey(const ValueKey('grid-cell-row-1:0'));
    final gesture = await tester.startGesture(
      tester.getCenter(target),
      kind: PointerDeviceKind.mouse,
      buttons: kSecondaryButton,
    );
    await tester.pump(const Duration(milliseconds: 600));
    expect(find.text('插入空格，本行向右移动'), findsNothing);

    await gesture.up();
    await tester.pumpAndSettle();
    expect(find.text('插入空格，本行向右移动'), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 600));
    expect(find.text('插入空格，本行向右移动'), findsOneWidget);
  });

  testWidgets('keeps a normal primary click free of the operation menu',
      (tester) async {
    final document = SmartGridDocument.empty(rows: 1, columns: 1);

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SmartGridEditor(document: document, onChanged: (_) {}),
      ),
    ));

    await tester.tap(find.byKey(const ValueKey('grid-cell-row-1:0')));
    await tester.pump(const Duration(milliseconds: 600));

    expect(find.text('插入空格，本行向右移动'), findsNothing);
  });

  testWidgets('opens row and column context menus without using type controls',
      (tester) async {
    final document = SmartGridDocument.empty(rows: 2, columns: 2);

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SmartGridEditor(document: document, onChanged: (_) {}),
      ),
    ));

    await _rightClick(tester, find.byKey(const ValueKey('grid-row-header-0')));
    expect(find.text('在上方插入谱行'), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();

    await _rightClick(
      tester,
      find.byKey(const ValueKey('grid-column-header-0')),
    );
    expect(find.text('在左侧插入一列'), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();

    await _rightClick(
      tester,
      find.byType(DropdownButtonFormField<SmartGridRowType>).first,
    );
    expect(find.text('在上方插入谱行'), findsNothing);
  });

  testWidgets('allows direct cell editing at the smallest and custom sizes',
      (tester) async {
    for (final percent in [0, 50]) {
      var document = SmartGridDocument.empty(rows: 1, columns: 1);

      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: StatefulBuilder(builder: (context, setState) {
            return SmartGridEditor(
              document: document,
              scale: TableScale(percent),
              onChanged: (next) => setState(() => document = next),
            );
          }),
        ),
      ));

      await tester.enterText(
        find.byKey(const ValueKey('grid-cell-row-1:0')),
        '3',
      );

      expect(document.rows.first.cells.first, '3', reason: '$percent%');
      expect(find.text('当前单元格内容'), findsNothing);
    }
  });
}

class _CountingIssues extends ListBase<SmartGridIssue> {
  _CountingIssues(this.values);
  final List<SmartGridIssue> values;
  int reads = 0;
  @override
  int get length => values.length;
  @override
  set length(int value) => throw UnsupportedError('read-only fixture');
  @override
  SmartGridIssue operator [](int index) {
    reads++;
    return values[index];
  }

  @override
  void operator []=(int index, SmartGridIssue value) =>
      throw UnsupportedError('read-only fixture');
}
