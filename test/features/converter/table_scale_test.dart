import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jianpu_keyboard/features/converter/table_scale.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('normalizes table scale into the supported range', () {
    expect(const TableScale(-1).normalized().percent, 0);
    expect(const TableScale(101).normalized().percent, 100);
    expect(const TableScale(87).normalized().presetLabel, '自定义 87%');
    expect(const TableScale(0).factor, .5);
    expect(const TableScale(100).factor, 1);
  });

  test('uses the agreed small, medium and large preset values', () {
    expect(TableScale.presets, {
      '小': 0,
      '中': 50,
      '大': 100,
    });
  });

  test('defaults new devices to the medium table size', () async {
    final persistence = TableScalePersistence(preferences: _PreferencesFake());

    expect((await persistence.load()).percent, 50);
  });

  test('persists an exact custom table scale locally', () async {
    final preferences = _PreferencesFake();
    final persistence = TableScalePersistence(preferences: preferences);

    await persistence.save(const TableScale(87));

    expect((await persistence.load()).percent, 87);
    expect(preferences.values[TableScalePersistence.storageKey],
        jsonEncode({'percent': 87}));
  });

  test('restores every preset and labels the medium scale', () async {
    final preferences = _PreferencesFake();
    final persistence = TableScalePersistence(preferences: preferences);

    for (final percent in [0, 50, 100]) {
      await persistence.save(TableScale(percent));
      expect((await persistence.load()).percent, percent);
    }
    expect(const TableScale(50).presetLabel, '中');
    expect(const TableScale(49).presetLabel, '自定义 49%');
  });

  test('migrates legacy table scale values to the 0 to 100 range', () async {
    final cases = <int, int>{
      25: 0,
      50: 0,
      65: 30,
      100: 100,
      130: 100,
      200: 100,
    };

    for (final entry in cases.entries) {
      final preferences = _PreferencesFake()
        ..values[TableScalePersistence.legacyStorageKey] =
            jsonEncode({'percent': entry.key});
      final persistence = TableScalePersistence(preferences: preferences);

      expect((await persistence.load()).percent, entry.value,
          reason: 'legacy ${entry.key}%');
      expect(preferences.values[TableScalePersistence.storageKey],
          jsonEncode({'percent': entry.value}));
    }
  });

  testWidgets(
      'the global control adjusts the shared scale one percent at a time',
      (tester) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child:
            const MaterialApp(home: Scaffold(body: GlobalTableScaleControl())),
      ),
    );

    await tester.tap(find.byType(DropdownButton<String>));
    await tester.pumpAndSettle();
    expect(find.text('小 0%'), findsOneWidget);
    expect(find.text('中 50%'), findsWidgets);
    expect(find.text('大 100%'), findsOneWidget);
    await tester.tap(find.text('中 50%').last);
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('缩小 1%'));

    expect(container.read(tableScaleProvider).percent, 49);
  });

  testWidgets('the global control validates and accepts visible percentages',
      (tester) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child:
            const MaterialApp(home: Scaffold(body: GlobalTableScaleControl())),
      ),
    );

    await tester.enterText(find.byType(TextField), '101');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();
    expect(find.text('请输入 0–100 的整数'), findsOneWidget);
    expect(container.read(tableScaleProvider).percent, 50);

    await tester.enterText(find.byType(TextField), '0');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();
    expect(container.read(tableScaleProvider).percent, 0);
  });
}

class _PreferencesFake extends Fake implements SharedPreferencesAsync {
  final values = <String, String>{};

  @override
  Future<String?> getString(String key) async => values[key];

  @override
  Future<void> setString(String key, String value) async {
    values[key] = value;
  }
}
