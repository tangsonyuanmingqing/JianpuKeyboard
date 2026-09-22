import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:jianpu_keyboard/app/app.dart';
import 'package:jianpu_keyboard/core/models/register.dart';
import 'package:jianpu_keyboard/features/converter/converter_providers.dart';
import 'package:jianpu_keyboard/features/converter/mapping_page.dart';
import 'package:jianpu_keyboard/features/converter/mapping_persistence.dart';
import 'package:jianpu_keyboard/infrastructure/shared_preferences_mapping_storage.dart';

const _smokeKey = 'jianpu_keyboard.keyboard_mapping.integration_smoke';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('default mapping remains after a second restart', (tester) async {
    final storage = SharedPreferencesMappingStorage(key: _smokeKey);
    expect(await storage.load(), isNull);
    final persistence = MappingPersistence(storage);
    final loaded = await persistence.load();
    expect(loaded.draft.middle?[2], 'D');

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
    expect(find.text('转换结果将显示在这里'), findsOneWidget);

    await tester.tap(find.byKey(const Key('open-mapping-button')));
    await tester.pumpAndSettle();
    final middleThree = find.byKey(mappingFieldKey(Register.middle, 3));
    await tester.ensureVisible(middleThree);
    expect(tester.widget<TextField>(middleThree).controller!.text, 'D');
    await tester.pageBack();
    await tester.pumpAndSettle();

    await tester.enterText(find.byKey(const Key('score-input')), '3');
    expect(find.text('D'), findsNothing);
    await tester.tap(find.byKey(const Key('convert-button')));
    await tester.pump();
    expect(find.text('D'), findsOneWidget);
    expect(await storage.load(), isNull);
  });
}
