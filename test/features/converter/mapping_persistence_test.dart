import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:jianpu_keyboard/core/mapping/keyboard_mapping.dart';
import 'package:jianpu_keyboard/core/models/register.dart';
import 'package:jianpu_keyboard/features/converter/mapping_persistence.dart';
import 'package:jianpu_keyboard/infrastructure/mapping_storage.dart';

void main() {
  const defaults = KeyboardMapping();
  final custom = KeyboardMapping.fromLists(
    low: defaults.low,
    middle: ['A', 'S', 'E', 'F', 'G', 'H', 'J'],
    high: defaults.high,
  );

  test('starts with defaults when there is no saved mapping', () async {
    final loaded = await MappingPersistence(_MemoryStorage()).load();

    expect(loaded.message, isNull);
    expect(loaded.draft.validate().mapping!.keyFor(3, Register.middle), 'D');
  });

  test('loads saved mapping into an editable draft', () async {
    final storage = _MemoryStorage(json: jsonEncode(custom.toJson()));

    final loaded = await MappingPersistence(storage).load();

    expect(loaded.message, isNull);
    expect(loaded.draft.validate().mapping!.keyFor(3, Register.middle), 'E');
  });

  test('keeps malformed JSON and starts with defaults', () async {
    final storage = _MemoryStorage(json: '{broken json}');

    final loaded = await MappingPersistence(storage).load();

    expect(loaded.message, contains('已损坏'));
    expect(loaded.draft.validate().mapping!.keyFor(3, Register.middle), 'D');
    expect(storage.json, '{broken json}');
  });

  test('keeps invalid mapping JSON and starts with defaults', () async {
    final storage = _MemoryStorage(json: '{"version":1}');

    final loaded = await MappingPersistence(storage).load();

    expect(loaded.message, contains('无效'));
    expect(loaded.draft.validate().mapping!.keyFor(3, Register.middle), 'D');
    expect(storage.json, '{"version":1}');
  });

  test('reports storage read failure separately from JSON failure', () async {
    final storage = _MemoryStorage()..failLoad = true;

    final loaded = await MappingPersistence(storage).load();

    expect(loaded.message, contains('读取'));
    expect(loaded.draft.validate().mapping!.keyFor(3, Register.middle), 'D');
  });

  test('queues reset after an unfinished save', () async {
    final gate = Completer<void>();
    final storage = _MemoryStorage()..saveGate = gate;
    final persistence = MappingPersistence(storage);

    final save = persistence.save(custom);
    final reset = persistence.clear();
    await Future<void>.delayed(Duration.zero);

    expect(storage.operations, ['save']);
    gate.complete();
    await Future.wait([save, reset]);
    await persistence.whenIdle;

    expect(storage.operations, ['save', 'clear']);
    expect(storage.json, isNull);
  });

  test('a failed save does not prevent a later write', () async {
    final storage = _MemoryStorage()..failNextSave = true;
    final persistence = MappingPersistence(storage);

    await expectLater(
      persistence.save(defaults),
      throwsA(isA<MappingStorageException>()),
    );
    await persistence.save(custom);
    await persistence.whenIdle;

    expect(storage.json, jsonEncode(custom.toJson()));
  });
}

class _MemoryStorage implements MappingStorage {
  String? json;
  bool failLoad = false;
  bool failNextSave = false;
  Completer<void>? saveGate;
  final List<String> operations = [];

  _MemoryStorage({this.json});

  @override
  Future<String?> load() async {
    if (failLoad) {
      throw const MappingStorageException('read failed');
    }
    return json;
  }

  @override
  Future<void> save(String value) async {
    operations.add('save');
    if (failNextSave) {
      failNextSave = false;
      throw const MappingStorageException('save failed');
    }
    if (saveGate != null) {
      await saveGate!.future;
    }
    json = value;
  }

  @override
  Future<void> clear() async {
    operations.add('clear');
    json = null;
  }
}
