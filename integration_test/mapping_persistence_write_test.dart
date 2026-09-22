import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:jianpu_keyboard/app/app.dart';
import 'package:jianpu_keyboard/core/mapping/keyboard_mapping.dart';
import 'package:jianpu_keyboard/core/models/register.dart';
import 'package:jianpu_keyboard/features/converter/converter_providers.dart';
import 'package:jianpu_keyboard/features/converter/mapping_page.dart';
import 'package:jianpu_keyboard/features/converter/mapping_persistence.dart';
import 'package:jianpu_keyboard/infrastructure/shared_preferences_mapping_storage.dart';

const _smokeKey = 'jianpu_keyboard.keyboard_mapping.integration_smoke';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('edit and save a mapping through the Windows app',
      (tester) async {
    final storage = SharedPreferencesMappingStorage(key: _smokeKey);
    await storage.clear();
    final persistence = MappingPersistence(storage);
    final loaded = await persistence.load();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          mappingPersistenceProvider.overrideWithValue(persistence),
          initialMappingDraftProvider.overrideWithValue(loaded.draft),
          initialMappingPersistenceMessageProvider.overrideWithValue(
            loaded.message,
          ),
        ],
        child: const JianpuKeyboardApp(),
      ),
    );

    await tester.tap(find.byKey(const Key('open-mapping-button')));
    await tester.pumpAndSettle();
    final middleThree = find.byKey(mappingFieldKey(Register.middle, 3));
    await tester.ensureVisible(middleThree);
    await tester.enterText(middleThree, 'E');
    await tester.pumpAndSettle();
    await persistence.whenIdle;

    final saved = KeyboardMapping.fromJson(jsonDecode((await storage.load())!));
    expect(saved.isValid, isTrue);
    expect(saved.mapping!.keyFor(3, Register.middle), 'E');
    expect(find.byKey(const Key('mapping-persistence-message')), findsNothing);

    await tester.enterText(middleThree, '');
    await tester.pumpAndSettle();
    await persistence.whenIdle;
    expect(find.byKey(const Key('mapping-unsaved-message')), findsOneWidget);
    final stillSaved = KeyboardMapping.fromJson(
      jsonDecode((await storage.load())!),
    );
    expect(stillSaved.mapping!.keyFor(3, Register.middle), 'E');
    await tester.enterText(middleThree, 'E');
    await tester.pumpAndSettle();
    await persistence.whenIdle;

    await tester.pageBack();
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('score-input')), '3');
    expect(find.text('E'), findsNothing);
    await tester.tap(find.byKey(const Key('convert-button')));
    await tester.pump();
    expect(find.text('E'), findsOneWidget);
  });
}
