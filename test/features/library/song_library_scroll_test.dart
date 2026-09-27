import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jianpu_keyboard/core/mapping/keyboard_mapping.dart';
import 'package:jianpu_keyboard/features/converter/smart_grid_codec.dart';
import 'package:jianpu_keyboard/features/converter/smart_grid_converter.dart';
import 'package:jianpu_keyboard/features/converter/smart_grid_document.dart';
import 'package:jianpu_keyboard/features/converter/smart_grid_editor.dart';
import 'package:jianpu_keyboard/features/library/song_library_page.dart';
import 'package:jianpu_keyboard/features/library/song_library_providers.dart';
import 'package:jianpu_keyboard/features/library/song_record.dart';

import '../../support/table_scroll_test_helpers.dart';

void main({bool native = false}) {
  TestVariant<Object?> windows = const DefaultTestVariant();
  if (!native) windows = TargetPlatformVariant.only(TargetPlatform.windows);
  testWidgets(
      'library preview rails stay independent of page scroll and dialog',
      (tester) async {
    if (!native) {
      tester.view.physicalSize = const Size(1000, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
    }
    final document = SmartGridDocument.empty(rows: 40, columns: 40);
    const mapping = KeyboardMapping();
    final conversion = const SmartGridConverter().convert(document, mapping);
    final date = DateTime.utc(2026, 9, 27);
    final song = SongRecord(
        id: 'scroll-test',
        title: '滚动回归',
        input: const SmartGridCodec().exportInput(document),
        editorMode: 'grid',
        gridDocument: document,
        result: SongResultSnapshot(
            output: conversion.result.output,
            mapping: mapping.toJson(),
            warnings: const [],
            savedAt: date),
        createdAt: date,
        updatedAt: date);
    await tester.pumpWidget(ProviderScope(overrides: [
      initialSongLibraryProvider.overrideWithValue([song]),
    ], child: const MaterialApp(home: SongDetailPage(songId: 'scroll-test'))));
    await tester.pumpAndSettle();
    final preview = find.byType(SmartGridOutputView);
    expect(preview, findsOneWidget);
    await tester.ensureVisible(preview);
    await tester.pumpAndSettle();
    final panel = find.byKey(const Key('resizable-panel-letter-grid'));
    final page = Scrollable.of(tester.element(preview)).position;
    final pageOffset = page.pixels;
    final lists = tester
        .widgetList<ListView>(
            find.descendant(of: preview, matching: find.byType(ListView)))
        .toList();
    void verify() {
      expect(page.pixels, pageOffset);
      expect(lists.first.controller!.offset,
          closeTo(lists.last.controller!.offset, .5));
    }

    expect(find.ancestor(of: preview, matching: find.byType(Scrollbar)),
        findsWidgets,
        reason: 'Only table-local automatic scrollbars are disabled.');
    await exerciseTableScrollbars(tester, panel, verify: verify);
    await tester.ensureVisible(find.text('应用保存的键位'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('应用保存的键位'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    page.jumpTo(pageOffset);
    await tester.pumpAndSettle();
    await exerciseTableScrollbars(tester, panel, verify: verify);
    await tester.pumpWidget(const SizedBox.shrink());
    expect(tester.takeException(), isNull);
  }, variant: windows);
}
