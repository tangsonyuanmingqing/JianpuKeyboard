import 'dart:convert';

import '../../core/mapping/keyboard_mapping.dart';
import '../../core/mapping/mapping_draft.dart';
import '../../infrastructure/mapping_storage.dart';

/// Mapping to use on startup, plus a message when the saved value could not
/// be used. A failed read never changes the stored text.
class MappingLoadResult {
  final MappingDraft draft;
  final String? message;

  const MappingLoadResult(this.draft, {this.message});
}

/// Coordinates mapping JSON with the raw-string storage boundary.
class MappingPersistence {
  final MappingStorage _storage;
  Future<void> _pendingWrite = Future<void>.value();

  MappingPersistence(this._storage);

  Future<MappingLoadResult> load() async {
    final String? json;
    try {
      json = await _storage.load();
    } on MappingStorageException {
      return _defaults('读取键盘映射失败，已使用默认映射。');
    }
    if (json == null) {
      return _defaults();
    }

    final Object? decoded;
    try {
      decoded = jsonDecode(json);
    } on FormatException {
      return _defaults('保存的键盘映射已损坏，已使用默认映射。');
    }
    final result = KeyboardMapping.fromJson(decoded);
    if (!result.isValid) {
      return _defaults('保存的键盘映射无效，已使用默认映射。');
    }
    return MappingLoadResult(MappingDraft.fromMapping(result.mapping!));
  }

  /// Saves only a validated, immutable mapping. Writes are ordered so a later
  /// edit or reset cannot be overwritten by an earlier write.
  Future<void> save(KeyboardMapping mapping) {
    final json = jsonEncode(mapping.toJson());
    return _enqueue(() => _storage.save(json));
  }

  Future<void> clear() => _enqueue(_storage.clear);

  /// Completes when queued writes, including failed ones, have settled.
  Future<void> get whenIdle => _pendingWrite;

  Future<void> _enqueue(Future<void> Function() write) {
    final current = _pendingWrite.then((_) => write());
    _pendingWrite = current.catchError((Object _) {});
    return current;
  }

  MappingLoadResult _defaults([String? message]) {
    return MappingLoadResult(
      MappingDraft.fromMapping(const KeyboardMapping()),
      message: message,
    );
  }
}
