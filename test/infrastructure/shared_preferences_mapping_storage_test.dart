import 'package:flutter_test/flutter_test.dart';
import 'package:jianpu_keyboard/infrastructure/mapping_storage.dart';
import 'package:jianpu_keyboard/infrastructure/shared_preferences_mapping_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  late _PreferencesFake preferences;
  late SharedPreferencesMappingStorage storage;

  setUp(() {
    preferences = _PreferencesFake();
    storage = SharedPreferencesMappingStorage(preferences: preferences);
  });

  test('missing mapping is null even when other preferences exist', () async {
    preferences.values['another.setting'] = 'untouched';

    expect(await storage.load(), isNull);
  });

  test('saves and overwrites raw JSON across storage instances', () async {
    await storage.save('{"version":1,"name":"first"}');
    await storage.save('{"version":1,"name":"second"}');
    final nextInstance =
        SharedPreferencesMappingStorage(preferences: preferences);

    expect(await nextInstance.load(), '{"version":1,"name":"second"}');
    expect(preferences.values, hasLength(1));
  });

  test('returns damaged text without parsing it', () async {
    const damaged = '{broken json}';

    await storage.save(damaged);

    expect(await storage.load(), damaged);
  });

  test('clear removes only the mapping and is safe when empty', () async {
    preferences.values['another.setting'] = 'untouched';
    await storage.save('{"version":1}');

    await storage.clear();
    await storage.clear();

    expect(await storage.load(), isNull);
    expect(preferences.values, {'another.setting': 'untouched'});
  });

  test('a custom key stays separate from the default mapping', () async {
    final isolated = SharedPreferencesMappingStorage(
      preferences: preferences,
      key: 'jianpu_keyboard.integration_test',
    );

    await storage.save('default');
    await isolated.save('test');
    await isolated.clear();

    expect(await storage.load(), 'default');
    expect(await isolated.load(), isNull);
  });

  test('wraps read failure and does not treat it as missing data', () async {
    final failure = StateError('read failed');
    preferences = _PreferencesFake(readFailure: failure);
    storage = SharedPreferencesMappingStorage(preferences: preferences);

    await expectLater(
      storage.load(),
      throwsA(
        isA<MappingStorageException>()
            .having((error) => error.message, 'message', '读取键盘映射失败。')
            .having((error) => error.cause, 'cause', same(failure)),
      ),
    );
  });

  test('wraps a wrong value type as a storage read failure', () async {
    await storage.save('{"version":1}');
    final key = preferences.values.keys.single;
    preferences.values[key] = 3;

    await expectLater(
      storage.load(),
      throwsA(
        isA<MappingStorageException>().having(
          (error) => error.cause,
          'cause',
          isA<TypeError>(),
        ),
      ),
    );
  });

  test('wraps save failure', () async {
    final failure = StateError('save failed');
    preferences = _PreferencesFake(saveFailure: failure);
    storage = SharedPreferencesMappingStorage(preferences: preferences);

    await expectLater(
      storage.save('{"version":1}'),
      throwsA(
        isA<MappingStorageException>()
            .having((error) => error.message, 'message', '保存键盘映射失败。')
            .having((error) => error.cause, 'cause', same(failure)),
      ),
    );
    expect(preferences.values, isEmpty);
  });

  test('wraps clear failure without deleting other preferences', () async {
    final failure = StateError('clear failed');
    preferences = _PreferencesFake(clearFailure: failure);
    storage = SharedPreferencesMappingStorage(preferences: preferences);
    preferences.values['another.setting'] = 'untouched';
    await storage.save('{"version":1}');

    await expectLater(
      storage.clear(),
      throwsA(
        isA<MappingStorageException>()
            .having((error) => error.message, 'message', '清除键盘映射失败。')
            .having((error) => error.cause, 'cause', same(failure)),
      ),
    );
    expect(preferences.values['another.setting'], 'untouched');
  });
}

class _PreferencesFake extends Fake implements SharedPreferencesAsync {
  final Map<String, Object> values = {};
  final Object? readFailure;
  final Object? saveFailure;
  final Object? clearFailure;

  _PreferencesFake({this.readFailure, this.saveFailure, this.clearFailure});

  @override
  Future<String?> getString(String key) async {
    if (readFailure != null) {
      throw readFailure!;
    }
    return values[key] as String?;
  }

  @override
  Future<void> setString(String key, String value) async {
    if (saveFailure != null) {
      throw saveFailure!;
    }
    values[key] = value;
  }

  @override
  Future<void> remove(String key) async {
    if (clearFailure != null) {
      throw clearFailure!;
    }
    values.remove(key);
  }
}
