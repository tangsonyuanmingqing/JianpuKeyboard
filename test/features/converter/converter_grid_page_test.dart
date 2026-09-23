import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jianpu_keyboard/features/converter/converter_page.dart';
import 'package:jianpu_keyboard/features/converter/converter_providers.dart';

void main() {
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
    await tester.ensureVisible(find.byKey(const Key('convert-button')));
    await tester.tap(find.byKey(const Key('convert-button')));
    await tester.pump();

    expect(container.read(conversionResultProvider)?.output, 'D\n晨');
    expect(find.byKey(const Key('export-inspection-image-button')),
        findsOneWidget);

    await tester.enterText(
      find.byKey(const ValueKey('grid-cell-row-1:0')),
      '4',
    );
    await tester.pump();

    expect(container.read(conversionResultProvider), isNull);
    expect(find.text('结果待更新'), findsOneWidget);
    expect(find.text('D\n晨'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
    container.dispose();
  });
}
