import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jianpu_keyboard/core/mapping/keyboard_mapping.dart';
import 'package:jianpu_keyboard/features/converter/resizable_panel.dart';
import 'package:jianpu_keyboard/features/converter/smart_grid_converter.dart';
import 'package:jianpu_keyboard/features/converter/smart_grid_document.dart';
import 'package:jianpu_keyboard/features/converter/smart_grid_editor.dart';
import 'package:jianpu_keyboard/features/converter/smart_grid_text_field.dart';
import 'package:jianpu_keyboard/features/converter/table_scale.dart';
import 'package:jianpu_keyboard/features/converter/table_scroll_frame.dart';

import '../../support/table_scroll_test_helpers.dart';

void main({bool native = false}) {
  TestVariant<Object?> windows = const DefaultTestVariant();
  if (!native) windows = TargetPlatformVariant.only(TargetPlatform.windows);
  testWidgets('selected cell does not swallow the painted horizontal thumb',
      (tester) async {
    var document = SmartGridDocument.empty(rows: 40, columns: 30);
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
      body: StatefulBuilder(
          builder: (context, setState) => SmartGridEditor(
                document: document,
                panelSize: const ResizablePanelSize(width: 500, height: 250),
                onChanged: (next) => setState(() => document = next),
              )),
    )));
    await tester.pumpAndSettle();
    final editor = find.byType(SmartGridEditor);
    final panel = find.byKey(const Key('resizable-panel-smart-grid'));
    final rect = tester.getRect(panel);
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: rect.bottomLeft + const Offset(80, -4));
    await tester.pumpAndSettle();
    expect(tableThumb(tester, panel, Axis.horizontal), isNotNull,
        reason: 'The thumb is available before selecting the cell.');

    final cell = find.byKey(const ValueKey('grid-cell-row-1:1'));
    await mouse.moveTo(tester.getCenter(cell));
    await mouse.down(tester.getCenter(cell));
    await mouse.up();
    await tester.pumpAndSettle();
    final field = tester.widget<EditableText>(
        find.descendant(of: cell, matching: find.byType(EditableText)));
    expect(field.focusNode.hasFocus, isTrue);
    await mouse.moveTo(rect.bottomLeft + const Offset(80, -4));
    await tester.pumpAndSettle();
    expect(tableThumb(tester, panel, Axis.horizontal), isNotNull,
        reason: 'Selecting a cell must not replace table scrollbar metrics.');
    final horizontal = tester
        .widget<SingleChildScrollView>(find.descendant(
            of: editor, matching: find.byType(SingleChildScrollView)))
        .controller!;
    final before = horizontal.offset;
    await dragTableThumb(tester, panel, Axis.horizontal, const Offset(80, 0));
    expect(horizontal.offset, greaterThan(before));
    expect(field.focusNode.hasFocus, isTrue);
    expect(document.selectedColumn, 1);
    await mouse.removePointer();
    await tester.pumpWidget(const SizedBox.shrink());
  }, variant: windows);

  testWidgets('real rails preserve selection, focus, caret, composing and undo',
      (tester) async {
    var document = SmartGridDocument.empty(rows: 40, columns: 30);
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: StatefulBuilder(
                builder: (context, setState) => SmartGridEditor(
                      document: document,
                      panelSize:
                          const ResizablePanelSize(width: 500, height: 250),
                      onChanged: (next) => setState(() => document = next),
                      onViewStateChanged: (next) =>
                          setState(() => document = next),
                    )))));
    await tester.pumpAndSettle();
    final cell = find.byKey(const ValueKey('grid-cell-row-2:0'));
    await tester.tap(cell, kind: PointerDeviceKind.mouse);
    await tester.pumpAndSettle();
    await tester.showKeyboard(cell);
    final controller = tester.widget<SmartGridTextField>(cell).controller;
    final editable =
        find.descendant(of: cell, matching: find.byType(EditableText));
    final state = tester.state<EditableTextState>(editable);
    final focus = tester.widget<EditableText>(editable).focusNode;
    const composing = TextEditingValue(
      text: '晨光',
      selection: TextSelection.collapsed(offset: 2),
      composing: TextRange(start: 0, end: 2),
    );
    tester.testTextInput.updateEditingValue(composing);
    await tester.pumpAndSettle();
    final panel = find.byKey(const Key('resizable-panel-smart-grid'));
    final lists = tester
        .widgetList<ReorderableListView>(find.byType(ReorderableListView))
        .toList();
    await exerciseTableScrollbars(tester, panel, verify: () {
      expect(focus.hasFocus, isTrue);
      expect(controller.value, composing);
      expect((document.selectedRow, document.selectedColumn), (1, 0));
      expect(lists.first.scrollController!.offset,
          closeTo(lists.last.scrollController!.offset, .5));
    });
    expect(tester.state<EditableTextState>(editable), same(state));
    tester.testTextInput.updateEditingValue(composing.copyWith(
        text: '晨光好',
        selection: const TextSelection.collapsed(offset: 3),
        composing: TextRange.empty));
    await tester.pumpAndSettle();
    expect(document.rows[1].cells.take(3), ['晨', '光', '好']);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft,
        physicalKey: PhysicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyZ,
        physicalKey: PhysicalKeyboardKey.keyZ);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft,
        physicalKey: PhysicalKeyboardKey.controlLeft);
    await tester.pumpAndSettle();
    expect(document.rows[1].cells.take(3), ['', '', '']);
    await tester.pumpWidget(const SizedBox.shrink());
  }, variant: windows);

  testWidgets('input scale, resize grip and row/column edits update real rails',
      (tester) async {
    var document = SmartGridDocument.empty(rows: 12, columns: 12);
    var scale = const TableScale();
    var size = const ResizablePanelSize(width: 500, height: 250);
    late StateSetter rebuild;
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: StatefulBuilder(
      builder: (context, setState) {
        rebuild = setState;
        return SmartGridEditor(
            document: document,
            scale: scale,
            panelSize: size,
            onChanged: (next) => setState(() => document = next),
            onPanelSizeChanged: (next) => setState(() => size = next));
      },
    ))));
    await tester.pumpAndSettle();
    final panel = find.byKey(const Key('resizable-panel-smart-grid'));
    final frame =
        tester.widget<TableScrollFrame>(find.byType(TableScrollFrame));
    await exerciseTableScrollbars(tester, panel);
    final oldSize = tester.getSize(panel);
    final grip = await tester.startGesture(
        tester.getCenter(find.byKey(const Key('smart-grid-resize-handle'))),
        kind: PointerDeviceKind.mouse);
    await grip.moveBy(const Offset(20, 20));
    await tester.pump();
    await grip.moveBy(const Offset(40, 40));
    await tester.pump();
    await grip.up();
    await tester.pumpAndSettle();
    expect(tester.getSize(panel).width, greaterThan(oldSize.width));
    expect(tester.getSize(panel).height, greaterThan(oldSize.height));
    expect(frame.horizontalController.offset, 0);
    expect(frame.verticalController.offset, 0);
    rebuild(() => scale = const TableScale(100));
    await tester.pumpAndSettle();
    await exerciseTableScrollbars(tester, panel);
    rebuild(() {
      while (document.rows.length > 1) {
        document = document.deleteRow(document.rows.length - 1);
      }
      while (document.columnCount > 1) {
        document = document.deleteColumn(document.columnCount - 1);
      }
      scale = const TableScale(50);
    });
    await tester.pumpAndSettle();
    expect(tableThumb(tester, panel, Axis.horizontal), isNull);
    expect(tableThumb(tester, panel, Axis.vertical), isNull);
    rebuild(() {
      for (var count = 0; count < 20; count++) {
        document = document
            .insertColumn(document.columnCount)
            .insertRow(document.rows.length, SmartGridRowType.score);
      }
    });
    await tester.pumpAndSettle();
    await exerciseTableScrollbars(tester, panel);
    await tester.pumpWidget(const SizedBox.shrink());
  }, variant: windows);

  testWidgets('output rails operate both axes and synchronize frozen rows',
      (tester) async {
    final document = SmartGridDocument.empty(rows: 40, columns: 30);
    final conversion =
        const SmartGridConverter().convert(document, const KeyboardMapping());
    Widget output(TableScale scale) => MaterialApp(
        home: Scaffold(
            body: SmartGridOutputView(
                document: document,
                conversion: conversion,
                scale: scale,
                panelSize: const ResizablePanelSize(width: 500, height: 250))));
    await tester.pumpWidget(output(const TableScale()));
    await tester.pumpAndSettle();
    final panel = find.byKey(const Key('resizable-panel-letter-grid'));
    final lists = tester.widgetList<ListView>(find.byType(ListView)).toList();
    void verify() => expect(lists.first.controller!.offset,
        closeTo(lists.last.controller!.offset, .5));
    await exerciseTableScrollbars(tester, panel, verify: verify);
    await tester.pumpWidget(output(const TableScale(75)));
    await tester.pumpAndSettle();
    await exerciseTableScrollbars(tester, panel, verify: verify);
    await tester.pumpWidget(const SizedBox.shrink());
  }, variant: windows);
}
