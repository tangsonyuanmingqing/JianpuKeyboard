import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jianpu_keyboard/core/mapping/keyboard_mapping.dart';
import 'package:jianpu_keyboard/core/mapping/mapping_draft.dart';
import 'package:jianpu_keyboard/core/models/register.dart';
import 'package:jianpu_keyboard/features/converter/converter_page.dart';
import 'package:jianpu_keyboard/features/converter/converter_providers.dart';
import 'package:jianpu_keyboard/features/converter/mapping_persistence.dart';
import 'package:jianpu_keyboard/infrastructure/mapping_storage.dart';

import '../../support/in_memory_mapping_storage.dart';

void main() {
  const defaults = KeyboardMapping();

  MappingDraft middleThree(MappingDraft draft, String value) {
    final middle = List<String>.of(draft.middle!)..[2] = value;
    return MappingDraft(low: draft.low, middle: middle, high: draft.high);
  }

  Future<({ProviderContainer container, MappingPersistence persistence})> start(
    MappingStorage storage,
  ) async {
    final persistence = MappingPersistence(storage);
    final loaded = await persistence.load();
    final container = ProviderContainer(
      overrides: [
        mappingPersistenceProvider.overrideWithValue(persistence),
        initialMappingDraftProvider.overrideWithValue(loaded.draft),
        initialMappingPersistenceMessageProvider.overrideWithValue(
          loaded.message,
        ),
      ],
    );
    addTearDown(container.dispose);
    return (container: container, persistence: persistence);
  }

  test('restores saved mapping and converts only when requested', () async {
    final mapping = KeyboardMapping.fromLists(
      low: defaults.low,
      middle: ['A', 'S', 'E', 'F', 'G', 'H', 'J'],
      high: defaults.high,
    );
    final storage = InMemoryMappingStorage(json: jsonEncode(mapping.toJson()));
    final session = await start(storage);

    expect(session.container.read(mappingDraftProvider).middle?[2], 'E');
    expect(session.container.read(conversionResultProvider), isNull);
    session.container.read(converterInputProvider.notifier).setScoreText('3');
    expect(session.container.read(conversionResultProvider), isNull);

    session.container.read(conversionResultProvider.notifier).convert();

    expect(session.container.read(conversionResultProvider)?.output, 'Ｅ');
  });

  test('a valid edit saves the mapping but never converts automatically',
      () async {
    final storage = InMemoryMappingStorage();
    final session = await start(storage);
    final container = session.container;
    container.read(converterInputProvider.notifier).setScoreText('3');
    container.read(conversionResultProvider.notifier).convert();
    expect(container.read(conversionResultProvider)?.output, 'Ｄ');

    container.read(mappingDraftProvider.notifier).updateMapping(
          middleThree(container.read(mappingDraftProvider), 'E'),
        );
    await session.persistence.whenIdle;

    expect(container.read(conversionResultProvider), isNull);
    expect(
      KeyboardMapping.fromJson(jsonDecode(storage.json!))
          .mapping!
          .keyFor(3, Register.middle),
      'E',
    );
    final restarted = await start(storage);
    expect(restarted.container.read(mappingDraftProvider).middle?[2], 'E');
    expect(restarted.container.read(conversionResultProvider), isNull);
  });

  test('invalid draft does not overwrite the last saved valid mapping',
      () async {
    final storage = InMemoryMappingStorage();
    final session = await start(storage);
    final container = session.container;
    container.read(mappingDraftProvider.notifier).updateMapping(
          middleThree(container.read(mappingDraftProvider), 'E'),
        );
    await session.persistence.whenIdle;
    final saved = storage.json;

    container.read(mappingDraftProvider.notifier).updateMapping(
          middleThree(container.read(mappingDraftProvider), ''),
        );
    container.read(converterInputProvider.notifier).setScoreText('3');
    container.read(conversionResultProvider.notifier).convert();

    expect(container.read(conversionResultProvider), isNull);
    expect(container.read(mappingDraftErrorsProvider).single.degree, 3);
    expect(storage.json, saved);
    final restarted = await start(storage);
    expect(restarted.container.read(mappingDraftProvider).middle?[2], 'E');
  });

  test('restoring defaults deletes the saved mapping without conversion',
      () async {
    final storage = InMemoryMappingStorage();
    final session = await start(storage);
    final container = session.container;
    container.read(converterInputProvider.notifier).setScoreText('3');
    container.read(mappingDraftProvider.notifier).updateMapping(
          middleThree(container.read(mappingDraftProvider), 'E'),
        );
    await session.persistence.whenIdle;
    container.read(conversionResultProvider.notifier).convert();
    expect(container.read(conversionResultProvider)?.output, 'Ｅ');

    container.read(mappingDraftProvider.notifier).restoreDefault();
    await session.persistence.whenIdle;

    expect(storage.json, isNull);
    expect(container.read(mappingDraftProvider).middle?[2], 'D');
    expect(container.read(conversionResultProvider), isNull);
    final restarted = await start(storage);
    expect(restarted.container.read(mappingDraftProvider).middle?[2], 'D');
  });

  test('save failure is visible without preventing manual conversion',
      () async {
    final storage = _FailingSaveStorage();
    final session = await start(storage);
    final container = session.container;
    container.read(converterInputProvider.notifier).setScoreText('3');

    container.read(mappingDraftProvider.notifier).updateMapping(
          middleThree(container.read(mappingDraftProvider), 'E'),
        );
    await session.persistence.whenIdle;
    await Future<void>.delayed(Duration.zero);

    expect(container.read(mappingPersistenceMessageProvider), contains('保存'));
    expect(container.read(conversionResultProvider), isNull);
    container.read(conversionResultProvider.notifier).convert();
    expect(container.read(conversionResultProvider)?.output, 'Ｅ');
  });

  test('a later successful save clears the previous failure message', () async {
    final storage = _FailOnceStorage();
    final session = await start(storage);
    final container = session.container;

    container.read(mappingDraftProvider.notifier).updateMapping(
          middleThree(container.read(mappingDraftProvider), 'E'),
        );
    await session.persistence.whenIdle;
    await Future<void>.delayed(Duration.zero);
    expect(container.read(mappingPersistenceMessageProvider), contains('保存'));

    container.read(mappingDraftProvider.notifier).updateMapping(
          middleThree(container.read(mappingDraftProvider), 'L'),
        );
    await session.persistence.whenIdle;
    await Future<void>.delayed(Duration.zero);

    expect(container.read(mappingPersistenceMessageProvider), isNull);
    expect(
      KeyboardMapping.fromJson(jsonDecode(storage.json!))
          .mapping!
          .keyFor(3, Register.middle),
      'L',
    );
  });

  test('failed reset warns that the old mapping may return on restart',
      () async {
    final storage = _FailingClearStorage();
    final session = await start(storage);
    final container = session.container;
    container.read(mappingDraftProvider.notifier).updateMapping(
          middleThree(container.read(mappingDraftProvider), 'E'),
        );
    await session.persistence.whenIdle;

    container.read(mappingDraftProvider.notifier).restoreDefault();
    await session.persistence.whenIdle;
    await Future<void>.delayed(Duration.zero);

    expect(container.read(mappingDraftProvider).middle?[2], 'D');
    expect(container.read(mappingPersistenceMessageProvider), contains('恢复默认'));
    final restarted = await start(storage);
    expect(restarted.container.read(mappingDraftProvider).middle?[2], 'E');
  });

  testWidgets('shows a startup storage warning on the converter page',
      (tester) async {
    final session = await start(InMemoryMappingStorage(json: '{broken json}'));
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: session.container,
        child: const MaterialApp(home: ConverterPage()),
      ),
    );

    expect(
      find.byKey(const Key('mapping-persistence-message')),
      findsOneWidget,
    );
    expect(find.textContaining('已损坏'), findsOneWidget);
  });
}

class _FailingSaveStorage extends InMemoryMappingStorage {
  @override
  Future<void> save(String value) async {
    throw const MappingStorageException('save failed');
  }
}

class _FailOnceStorage extends InMemoryMappingStorage {
  bool _failed = false;

  @override
  Future<void> save(String value) async {
    if (!_failed) {
      _failed = true;
      throw const MappingStorageException('save failed');
    }
    await super.save(value);
  }
}

class _FailingClearStorage extends InMemoryMappingStorage {
  @override
  Future<void> clear() async {
    throw const MappingStorageException('clear failed');
  }
}
