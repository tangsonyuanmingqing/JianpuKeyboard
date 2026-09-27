import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jianpu_keyboard/features/converter/converter_page.dart';
import 'package:jianpu_keyboard/features/converter/converter_panel_layout_persistence.dart';
import 'package:jianpu_keyboard/features/converter/converter_providers.dart';
import 'package:jianpu_keyboard/features/converter/resizable_panel.dart';
import 'package:jianpu_keyboard/features/converter/smart_grid_editor.dart';

void main() {
  for (final large in [false, true]) {
    testWidgets('restores injected ${large ? "large" : "default"} grid layout',
        (tester) async {
      tester.view.physicalSize = const Size(1400, 1500);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final layout = _PanelLayoutFake(large
          ? const {'smart-grid': ResizablePanelSize(width: 1230, height: 1200)}
          : const {});
      final container = ProviderContainer(overrides: [
        initialEditorModeProvider.overrideWithValue(ConverterEditorMode.grid),
        converterPanelLayoutPersistenceProvider.overrideWithValue(layout),
      ]);
      await tester.pumpWidget(UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: ConverterPage()),
      ));
      await tester.pumpAndSettle();
      final editor =
          tester.widget<SmartGridEditor>(find.byType(SmartGridEditor));
      expect(editor.panelSize.isDefault, !large);
      if (large) {
        expect(
            tester.getSize(find.byKey(const Key('resizable-panel-smart-grid'))),
            const Size(1230, 1200));
      }
      expect(layout.loads, 1);
      expect(layout.saves, 0);
      await tester.pumpWidget(const SizedBox.shrink());
      container.dispose();
    });
  }
  testWidgets('converts a grid and keeps the previous result visibly stale',
      (tester) async {
    final container = ProviderContainer(overrides: [
      initialEditorModeProvider.overrideWithValue(ConverterEditorMode.grid),
    ]);
    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: const MaterialApp(home: ConverterPage()),
    ));

    await tester.enterText(
      find.byKey(const ValueKey('grid-cell-row-1:0')),
      '3',
    );
    await tester.enterText(
      find.byKey(const ValueKey('grid-cell-row-2:0')),
      '晨',
    );
    expect(container.read(smartGridDocumentProvider).rows[0].cells[0], '3');
    expect(container.read(smartGridDocumentProvider).rows[1].cells[0], '晨');
    expect(container.read(editorModeProvider), ConverterEditorMode.grid);
    expect(container.read(mappingDraftProvider).validate().isValid, isTrue);
    await tester.ensureVisible(find.byKey(const Key('convert-button')));
    await tester.tap(find.byKey(const Key('convert-button')));
    await tester.pump();

    expect(container.read(conversionResultProvider)?.output, 'Ｄ\n晨');
    expect(find.byKey(const Key('export-inspection-image-button')),
        findsOneWidget);

    await tester.enterText(
      find.byKey(const ValueKey('grid-cell-row-1:0')),
      '4',
    );
    await tester.pump();

    expect(container.read(conversionResultProvider), isNull);
    expect(find.text('结果待更新'), findsOneWidget);
    expect(find.text('Ｄ\n晨'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
    container.dispose();
  });
}

class _PanelLayoutFake extends ConverterPanelLayoutPersistence {
  _PanelLayoutFake(this.sizes);
  final Map<String, ResizablePanelSize> sizes;
  int loads = 0;
  int saves = 0;

  @override
  Future<Map<String, ResizablePanelSize>> load() async {
    loads++;
    return sizes;
  }

  @override
  Future<void> save(Map<String, ResizablePanelSize> sizes) async => saves++;
}
