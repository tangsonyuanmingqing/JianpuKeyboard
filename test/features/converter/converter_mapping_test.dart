import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jianpu_keyboard/core/mapping/keyboard_mapping.dart';
import 'package:jianpu_keyboard/core/mapping/mapping_draft.dart';
import 'package:jianpu_keyboard/core/models/register.dart';
import 'package:jianpu_keyboard/features/converter/converter_providers.dart';
import 'package:jianpu_keyboard/features/converter/mapping_persistence.dart';

import '../../support/in_memory_mapping_storage.dart';

void main() {
  const defaults = KeyboardMapping();

  List<String> replaceKey(List<String> keys, int degree, String value) {
    return [
      for (var index = 0; index < keys.length; index++)
        if (index == degree - 1) value else keys[index],
    ];
  }

  MappingDraft draftWithMiddle(int degree, String value) {
    return MappingDraft(
      low: defaults.low,
      middle: replaceKey(defaults.middle, degree, value),
      high: defaults.high,
    );
  }

  ProviderContainer container() {
    final result = ProviderContainer(
      overrides: [
        mappingPersistenceProvider.overrideWithValue(
          MappingPersistence(InMemoryMappingStorage()),
        ),
      ],
    );
    addTearDown(result.dispose);
    return result;
  }

  test('converts middle 3 to D with the default mapping', () {
    final provider = container();
    provider.read(converterInputProvider.notifier).setScoreText('3');

    provider.read(conversionResultProvider.notifier).convert();

    expect(provider.read(conversionResultProvider)?.output, 'Ｄ');
    expect(provider.read(mappingDraftErrorsProvider), isEmpty);
  });

  test('clears the result when the mapping changes and does not convert', () {
    final provider = container();
    provider.read(converterInputProvider.notifier).setScoreText('3');
    provider.read(conversionResultProvider.notifier).convert();
    expect(provider.read(conversionResultProvider)?.output, 'Ｄ');

    provider
        .read(mappingDraftProvider.notifier)
        .updateMapping(draftWithMiddle(3, 'E'));

    expect(provider.read(conversionResultProvider), isNull);
    expect(provider.read(mappingDraftProvider).middle?[2], 'E');
  });

  test('does not convert when only the mapping draft changes', () {
    final provider = container();
    provider.read(converterInputProvider.notifier).setScoreText('3');

    provider
        .read(mappingDraftProvider.notifier)
        .updateMapping(draftWithMiddle(3, 'E'));

    expect(provider.read(conversionResultProvider), isNull);
  });

  test('uses the current mapping after convert is requested', () {
    final provider = container();
    provider.read(converterInputProvider.notifier).setScoreText('3');
    provider
        .read(mappingDraftProvider.notifier)
        .updateMapping(draftWithMiddle(3, 'E'));

    provider.read(conversionResultProvider.notifier).convert();

    expect(provider.read(conversionResultProvider)?.output, 'Ｅ');
    expect(provider.read(mappingDraftErrorsProvider), isEmpty);
  });

  test('restores the default mapping without converting', () {
    final provider = container();
    provider.read(converterInputProvider.notifier).setScoreText('3');
    provider
        .read(mappingDraftProvider.notifier)
        .updateMapping(draftWithMiddle(3, 'E'));
    provider.read(conversionResultProvider.notifier).convert();
    expect(provider.read(conversionResultProvider)?.output, 'Ｅ');

    provider.read(mappingDraftProvider.notifier).restoreDefault();

    expect(provider.read(conversionResultProvider), isNull);
    expect(provider.read(mappingDraftProvider).middle, defaults.middle);
    expect(provider.read(mappingDraftErrorsProvider), isEmpty);

    provider.read(conversionResultProvider.notifier).convert();
    expect(provider.read(conversionResultProvider)?.output, 'Ｄ');
  });

  test('keeps the result empty when the mapping draft is invalid', () {
    final provider = container();
    provider.read(converterInputProvider.notifier).setScoreText('3');
    provider.read(conversionResultProvider.notifier).convert();
    expect(provider.read(conversionResultProvider)?.output, 'Ｄ');

    provider
        .read(mappingDraftProvider.notifier)
        .updateMapping(draftWithMiddle(3, ''));
    provider.read(conversionResultProvider.notifier).convert();

    expect(provider.read(conversionResultProvider), isNull);
    final error = provider.read(mappingDraftErrorsProvider).single;
    expect(error.register, Register.middle);
    expect(error.degree, 3);
    expect(error.value, '');
  });

  test('converts duplicated keys and reports a mapping warning', () {
    final provider = container();
    provider.read(converterInputProvider.notifier).setScoreText('1 2');
    provider
        .read(mappingDraftProvider.notifier)
        .updateMapping(draftWithMiddle(2, 'A'));

    provider.read(conversionResultProvider.notifier).convert();

    final result = provider.read(conversionResultProvider);
    expect(result, isNotNull);
    expect(result!.output, 'Ａ Ａ');
    expect(result.errors, isEmpty);
    expect(result.warnings.single.message, '键 A 被多个音符使用');
    expect(provider.read(mappingDraftErrorsProvider), isEmpty);
  });

  test('clearing score input keeps the mapping draft', () {
    final provider = container();
    provider
        .read(mappingDraftProvider.notifier)
        .updateMapping(draftWithMiddle(3, 'E'));

    provider.read(converterInputProvider.notifier).clear();

    expect(provider.read(mappingDraftProvider).middle?[2], 'E');
    provider.read(converterInputProvider.notifier).setScoreText('3');
    provider.read(conversionResultProvider.notifier).convert();
    expect(provider.read(conversionResultProvider)?.output, 'Ｅ');
  });
}
