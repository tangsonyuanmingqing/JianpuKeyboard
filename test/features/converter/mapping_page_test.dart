import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jianpu_keyboard/core/models/register.dart';
import 'package:jianpu_keyboard/features/converter/converter_page.dart';
import 'package:jianpu_keyboard/features/converter/converter_providers.dart';
import 'package:jianpu_keyboard/features/converter/mapping_page.dart';

void main() {
  const defaultRows = {
    'low': ['Z', 'X', 'C', 'V', 'B', 'N', 'M'],
    'middle': ['A', 'S', 'D', 'F', 'G', 'H', 'J'],
    'high': ['Q', 'W', 'E', 'R', 'T', 'Y', 'U'],
  };

  Future<ProviderContainer> pumpPage(WidgetTester tester) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: ConverterPage()),
      ),
    );
    return container;
  }

  Future<void> openMapping(WidgetTester tester) async {
    await tester.tap(find.byKey(const Key('open-mapping-button')));
    await tester.pumpAndSettle();
  }

  Future<void> editField(
    WidgetTester tester,
    Register register,
    int degree,
    String value,
  ) async {
    final field = find.byKey(mappingFieldKey(register, degree));
    await tester.ensureVisible(field);
    await tester.enterText(field, value);
    await tester.pump();
  }

  String fieldText(WidgetTester tester, Register register, int degree) {
    return tester
        .widget<TextField>(find.byKey(mappingFieldKey(register, degree)))
        .controller!
        .text;
  }

  testWidgets('opens the keyboard mapping page from the converter',
      (tester) async {
    await pumpPage(tester);

    await openMapping(tester);

    expect(find.text('键盘映射'), findsOneWidget);
    expect(find.text('低音'), findsOneWidget);
    expect(find.text('中音'), findsOneWidget);
    expect(find.text('高音'), findsOneWidget);
  });

  testWidgets('shows the default 21 keys', (tester) async {
    await pumpPage(tester);
    await openMapping(tester);

    for (final register in Register.values) {
      final letters = defaultRows[register.name]!;
      for (var degree = 1; degree <= 7; degree++) {
        expect(
          fieldText(tester, register, degree),
          letters[degree - 1],
        );
      }
    }
  });

  testWidgets('updates the draft when middle 3 changes to E', (tester) async {
    final container = await pumpPage(tester);
    await openMapping(tester);

    await editField(tester, Register.middle, 3, 'E');

    expect(fieldText(tester, Register.middle, 3), 'E');
    expect(container.read(mappingDraftProvider).middle?[2], 'E');
  });

  testWidgets('stores a lowercase letter as uppercase', (tester) async {
    final container = await pumpPage(tester);
    await openMapping(tester);

    await editField(tester, Register.middle, 3, 'e');

    expect(fieldText(tester, Register.middle, 3), 'E');
    expect(container.read(mappingDraftProvider).middle?[2], 'E');
    expect(find.byKey(const Key('mapping-error-middle-3')), findsNothing);
  });

  testWidgets('shows mapping errors for empty, digit, symbol and extra text',
      (tester) async {
    final container = await pumpPage(tester);
    await openMapping(tester);

    await editField(tester, Register.middle, 3, '');
    expect(find.text('中音 3：请输入 A-Z 字母'), findsOneWidget);
    expect(container.read(mappingDraftProvider).middle?[2], '');

    await editField(tester, Register.middle, 3, '1');
    expect(find.text('中音 3：请输入 A-Z 字母'), findsNothing);
    expect(find.text('中音 3 必须是一个英文字母。'), findsOneWidget);
    expect(container.read(mappingDraftProvider).middle?[2], '1');

    await editField(tester, Register.middle, 3, '-');
    expect(find.text('中音 3 必须是一个英文字母。'), findsOneWidget);
    expect(container.read(mappingDraftProvider).middle?[2], '-');

    await editField(tester, Register.middle, 3, 'AB');
    expect(find.text('中音 3 必须是一个英文字母。'), findsOneWidget);
    expect(container.read(mappingDraftProvider).middle?[2], 'AB');
  });

  testWidgets('does not convert after a mapping edit until convert is pressed',
      (tester) async {
    await pumpPage(tester);
    await tester.enterText(find.byKey(const Key('score-input')), '3');
    await tester.tap(find.byKey(const Key('convert-button')));
    await tester.pump();
    expect(find.text('D'), findsOneWidget);

    await openMapping(tester);
    await editField(tester, Register.middle, 3, 'E');
    await tester.pageBack();
    await tester.pumpAndSettle();

    expect(find.text('D'), findsNothing);
    expect(find.text('E'), findsNothing);
    expect(find.text('转换结果将显示在这里'), findsOneWidget);

    await tester.tap(find.byKey(const Key('convert-button')));
    await tester.pump();
    expect(find.text('E'), findsOneWidget);
  });

  testWidgets('restores the default mapping without converting',
      (tester) async {
    await pumpPage(tester);
    await tester.enterText(find.byKey(const Key('score-input')), '3');
    await tester.tap(find.byKey(const Key('convert-button')));
    await tester.pump();

    await openMapping(tester);
    await editField(tester, Register.middle, 3, 'E');
    await tester.tap(find.byKey(const Key('restore-mapping-button')));
    await tester.pumpAndSettle();

    expect(fieldText(tester, Register.middle, 3), 'D');
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.text('E'), findsNothing);
    expect(find.text('转换结果将显示在这里'), findsOneWidget);

    await tester.tap(find.byKey(const Key('convert-button')));
    await tester.pump();
    expect(find.text('D'), findsOneWidget);
  });

  testWidgets('shows a duplicate-key warning and still converts',
      (tester) async {
    await pumpPage(tester);
    await openMapping(tester);
    await editField(tester, Register.low, 1, 'A');
    await editField(tester, Register.middle, 3, 'A');

    expect(find.text('⚠ 键 A 被多个音符使用'), findsWidgets);

    await tester.pageBack();
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('score-input')), '3');
    await tester.tap(find.byKey(const Key('convert-button')));
    await tester.pump();

    expect(find.text('A'), findsOneWidget);
    expect(find.text('键 A 被多个音符使用'), findsOneWidget);
  });

  testWidgets('keeps the mapping draft when the converter input is cleared',
      (tester) async {
    final container = await pumpPage(tester);
    await openMapping(tester);
    await editField(tester, Register.middle, 3, 'E');
    await tester.pageBack();
    await tester.pumpAndSettle();

    await tester.enterText(find.byKey(const Key('score-input')), '3');
    await tester.enterText(find.byKey(const Key('lyrics-input')), '我');
    await tester.tap(find.byKey(const Key('convert-button')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('clear-button')));
    await tester.pump();

    expect(
      tester
          .widget<TextField>(find.byKey(const Key('score-input')))
          .controller!
          .text,
      '',
    );
    expect(container.read(mappingDraftProvider).middle?[2], 'E');

    await openMapping(tester);
    expect(fieldText(tester, Register.middle, 3), 'E');
  });

  testWidgets('lays out the mapping page in a narrow window', (tester) async {
    await _pumpMappingPageAt(tester, const Size(360, 800));
    await editField(tester, Register.middle, 3, '');
    expect(find.text('低音'), findsOneWidget);
    expect(find.text('中音 3：请输入 A-Z 字母'), findsOneWidget);
  });

  testWidgets('lays out the mapping page in a wide window', (tester) async {
    await _pumpMappingPageAt(tester, const Size(1280, 800));
    await editField(tester, Register.middle, 3, '');
    expect(find.text('低音'), findsOneWidget);
    expect(find.text('中音'), findsOneWidget);
    expect(find.text('高音'), findsOneWidget);
    expect(find.text('中音 3：请输入 A-Z 字母'), findsOneWidget);
  });
}

Future<void> _pumpMappingPageAt(WidgetTester tester, Size size) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  final container = ProviderContainer();
  addTearDown(container.dispose);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: const MaterialApp(home: ConverterPage()),
    ),
  );
  await tester.tap(find.byKey(const Key('open-mapping-button')));
  await tester.pumpAndSettle();
}
