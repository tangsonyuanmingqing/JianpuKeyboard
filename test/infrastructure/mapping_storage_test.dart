import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:jianpu_keyboard/core/mapping/keyboard_mapping.dart';
import 'package:jianpu_keyboard/core/mapping/keyboard_mapping_json.dart';
import 'package:jianpu_keyboard/core/models/register.dart';
import 'package:jianpu_keyboard/infrastructure/mapping_storage.dart';

void main() {
  late InMemoryMappingStorage storage;

  setUp(() {
    storage = InMemoryMappingStorage();
  });

  test('loads null when nothing has been saved', () async {
    expect(await storage.load(), isNull);
  });

  test('returns the saved json', () async {
    const json = '{"version":1}';

    await storage.save(json);

    expect(await storage.load(), json);
  });

  test('overwrites the previous json', () async {
    await storage.save('{"version":1,"name":"first"}');
    await storage.save('{"version":1,"name":"second"}');

    expect(await storage.load(), '{"version":1,"name":"second"}');
  });

  test('clears a saved json', () async {
    await storage.save('{"version":1}');

    await storage.clear();

    expect(await storage.load(), isNull);
  });

  test('clear succeeds when storage is already empty', () async {
    await storage.clear();

    expect(await storage.load(), isNull);
  });

  test('round-trips a mapping through stored json text', () async {
    const mapping = KeyboardMapping();
    final encoded = jsonEncode(mapping.toJson());

    await storage.save(encoded);

    final loaded = await storage.load();
    expect(loaded, encoded);

    final result = KeyboardMapping.fromJson(jsonDecode(loaded!));
    expect(result.isValid, isTrue);
    expect(result.warnings, isEmpty);
    expect(result.mapping!.low, mapping.low);
    expect(result.mapping!.middle, mapping.middle);
    expect(result.mapping!.high, mapping.high);
    expect(result.mapping!.keyFor(3, Register.middle), 'D');
  });

  test('returns damaged text and leaves decoding to fromJson', () async {
    const damaged = '{broken json}';

    await storage.save(damaged);

    final loaded = await storage.load();
    expect(loaded, damaged);

    final result = KeyboardMapping.fromJson(loaded);
    expect(result.isValid, isFalse);
    expect(result.mapping, isNull);
    expect(
      result.errors.single.issue,
      KeyboardMappingJsonIssue.invalidType,
    );
  });

  test('does not store duplicate-key warnings inside the json', () async {
    final mapping = KeyboardMapping.fromLists(
      low: ['A', 'A', 'C', 'D', 'E', 'F', 'G'],
      middle: ['H', 'I', 'J', 'K', 'L', 'M', 'N'],
      high: ['O', 'P', 'Q', 'R', 'S', 'T', 'U'],
    );
    final encoded = jsonEncode(mapping.toJson());
    expect(encoded.contains('键'), isFalse);

    await storage.save(encoded);

    final result = KeyboardMapping.fromJson(
      jsonDecode((await storage.load())!),
    );
    expect(result.isValid, isTrue);
    expect(result.warnings.single.message, '键 A 被多个音符使用');
  });

  test('reports a read failure instead of missing data', () {
    final failing = _FailingMappingStorage();

    expect(
      failing.load,
      throwsA(
        isA<MappingStorageException>().having(
          (error) => error.message,
          'message',
          '读取键盘映射失败。',
        ),
      ),
    );
  });
}

/// One JSON string in memory. Production code does not use this type.
class InMemoryMappingStorage implements MappingStorage {
  String? _stored;

  @override
  Future<String?> load() async => _stored;

  @override
  Future<void> save(String json) async {
    _stored = json;
  }

  @override
  Future<void> clear() async {
    _stored = null;
  }
}

class _FailingMappingStorage implements MappingStorage {
  @override
  Future<String?> load() async {
    throw const MappingStorageException('读取键盘映射失败。');
  }

  @override
  Future<void> save(String json) async {}

  @override
  Future<void> clear() async {}
}
