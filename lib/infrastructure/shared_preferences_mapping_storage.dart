import 'package:shared_preferences/shared_preferences.dart';

import 'mapping_storage.dart';

/// Stores one raw mapping JSON string in platform preferences.
///
/// JSON decoding and selection of a default mapping belong to the caller.
class SharedPreferencesMappingStorage implements MappingStorage {
  static const _key = 'jianpu_keyboard.keyboard_mapping';

  SharedPreferencesAsync? _preferences;

  SharedPreferencesMappingStorage({SharedPreferencesAsync? preferences})
      : _preferences = preferences;

  SharedPreferencesAsync get _store =>
      _preferences ??= SharedPreferencesAsync();

  @override
  Future<String?> load() async {
    try {
      return await _store.getString(_key);
    } on Object catch (error, stackTrace) {
      Error.throwWithStackTrace(
        MappingStorageException('读取键盘映射失败。', cause: error),
        stackTrace,
      );
    }
  }

  @override
  Future<void> save(String json) async {
    try {
      await _store.setString(_key, json);
    } on Object catch (error, stackTrace) {
      Error.throwWithStackTrace(
        MappingStorageException('保存键盘映射失败。', cause: error),
        stackTrace,
      );
    }
  }

  @override
  Future<void> clear() async {
    try {
      await _store.remove(_key);
    } on Object catch (error, stackTrace) {
      Error.throwWithStackTrace(
        MappingStorageException('清除键盘映射失败。', cause: error),
        stackTrace,
      );
    }
  }
}
