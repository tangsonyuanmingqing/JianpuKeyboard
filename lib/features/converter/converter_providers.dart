import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/converter/jianpu_converter.dart';
import '../../core/mapping/keyboard_mapping.dart';
import '../../core/mapping/mapping_draft.dart';
import '../../core/models/conversion_result.dart';
import '../../core/models/validation_message.dart';
import '../../infrastructure/shared_preferences_mapping_storage.dart';
import '../../infrastructure/persistence_load_result.dart';
import '../../infrastructure/recovery_providers.dart';
import '../../infrastructure/recovery_snapshot_repository.dart';
import '../../infrastructure/storage_health.dart';
import '../../infrastructure/persistence_state_notifiers.dart';
import 'converter_input.dart';
import 'converter_draft_persistence.dart';
import 'mapping_persistence.dart';
import 'smart_grid_codec.dart';
import 'smart_grid_document.dart';

class ConverterInputNotifier extends Notifier<ConverterInput> {
  Timer? _saveTimer;
  Timer? _snapshotTimer;
  Future<void>? _lastWrite;
  var _writeRevision = 0;
  var _snapshotDirty = false;
  DateTime? _lastSnapshotAt;

  @override
  ConverterInput build() {
    ref.onDispose(() {
      _saveTimer?.cancel();
      _snapshotTimer?.cancel();
    });
    return ref.read(initialConverterInputProvider);
  }

  void setScoreText(String value) {
    if (state.scoreText == value) {
      return;
    }
    _replace(ConverterInput(scoreText: value, lyricsText: state.lyricsText));
  }

  void setLyricsText(String value) {
    if (state.lyricsText == value) {
      return;
    }
    _replace(ConverterInput(scoreText: state.scoreText, lyricsText: value));
  }

  ConverterInput clear() {
    final previous = state;
    _saveTimer?.cancel();
    _writeRevision++;
    _snapshotDirty = true;
    state = const ConverterInput();
    ref.read(conversionResultProvider.notifier).clear();
    _lastWrite = _clearSavedDraft(_writeRevision);
    unawaited(_lastWrite!.catchError((Object _) {}));
    return previous;
  }

  void restore(ConverterInput input) {
    _replace(input, saveImmediately: true);
  }

  void replace(ConverterInput input) => _replace(input);

  void saveCurrentDraftSoon() {
    _snapshotDirty = true;
    _saveTimer?.cancel();
    final revision = ++_writeRevision;
    _saveTimer = Timer(ref.read(draftSaveDelayProvider), () {
      _lastWrite = _saveDraft(state, revision);
      unawaited(_lastWrite!.catchError((Object _) {}));
    });
  }

  void _replace(ConverterInput input, {bool saveImmediately = false}) {
    state = input;
    _snapshotDirty = true;
    ref.read(conversionResultProvider.notifier).clear();
    _saveTimer?.cancel();
    final revision = ++_writeRevision;
    if (saveImmediately) {
      _lastWrite = _saveDraft(input, revision);
      unawaited(_lastWrite!.catchError((Object _) {}));
      return;
    }
    _saveTimer = Timer(ref.read(draftSaveDelayProvider), () {
      _lastWrite = _saveDraft(input, revision);
      unawaited(_lastWrite!.catchError((Object _) {}));
    });
  }

  Future<void> flush() async {
    _saveTimer?.cancel();
    final revision = ++_writeRevision;
    _lastWrite = _saveDraft(state, revision);
    await _lastWrite;
    await ref.read(converterDraftPersistenceProvider).flush();
    await ref.read(recoverySnapshotRepositoryProvider).flush();
  }

  Future<void> retry() => flush();

  Future<void> _saveDraft(ConverterInput input, int revision) async {
    if (ref.read(draftStorageHealthProvider).blocksWrites) {
      const message = '草稿需要先恢复或重置，当前修改尚未保存。';
      ref.read(draftPersistenceMessageProvider.notifier).set(message);
      ref.read(draftWriteStateProvider.notifier).failed(message);
      throw StateError(message);
    }
    ref.read(draftWriteStateProvider.notifier).saving();
    try {
      await ref.read(converterDraftPersistenceProvider).save(
            input,
            songTitle: ref.read(songTitleProvider),
            songId: ref.read(currentSongIdProvider),
            gridDocument: ref.read(smartGridDocumentProvider),
            editorMode: ref.read(editorModeProvider).name,
          );
      final backupSucceeded = await _createDraftSnapshotIfDue();
      if (revision == _writeRevision) {
        if (backupSucceeded) {
          ref.read(draftPersistenceMessageProvider.notifier).clear();
        }
        ref.read(draftWriteStateProvider.notifier).saved();
      }
    } on Object {
      if (revision == _writeRevision) {
        const message = '保存草稿失败，本次编辑可能无法在重启后恢复。';
        ref.read(draftPersistenceMessageProvider.notifier).set(message);
        ref.read(draftWriteStateProvider.notifier).failed(message);
      }
      rethrow;
    }
  }

  Future<void> _clearSavedDraft(int revision) async {
    if (ref.read(draftStorageHealthProvider).blocksWrites) {
      throw StateError('草稿需要先恢复或重置。');
    }
    ref.read(draftWriteStateProvider.notifier).saving();
    try {
      await ref.read(converterDraftPersistenceProvider).clear();
      if (revision == _writeRevision) {
        ref.read(draftPersistenceMessageProvider.notifier).clear();
        ref.read(draftWriteStateProvider.notifier).saved();
      }
    } on Object {
      if (revision == _writeRevision) {
        const message = '清除草稿失败，重启后可能恢复原来的内容。';
        ref.read(draftPersistenceMessageProvider.notifier).set(message);
        ref.read(draftWriteStateProvider.notifier).failed(message);
      }
      rethrow;
    }
  }

  Future<bool> _createDraftSnapshotIfDue() async {
    if (!_snapshotDirty || ref.read(draftStorageHealthProvider).blocksWrites) {
      return true;
    }
    final now = DateTime.now();
    final interval = ref.read(draftSnapshotIntervalProvider);
    if (_lastSnapshotAt != null &&
        now.difference(_lastSnapshotAt!) < interval) {
      _scheduleSnapshot(
        interval - now.difference(_lastSnapshotAt!),
      );
      return true;
    }
    final raw = ConverterDraftPersistence.encodeDocument(
      state,
      songTitle: ref.read(songTitleProvider),
      songId: ref.read(currentSongIdProvider),
      gridDocument: ref.read(smartGridDocumentProvider),
      editorMode: ref.read(editorModeProvider).name,
    );
    try {
      await ref.read(recoverySnapshotRepositoryProvider).create(
            type: RecoverySnapshotType.draft,
            payload: jsonDecode(raw),
            source: RecoverySnapshotSource.automatic,
            deduplicate: true,
          );
      _snapshotDirty = false;
      _lastSnapshotAt = now;
      _snapshotTimer?.cancel();
      _snapshotTimer = null;
      return true;
    } on Object {
      ref
          .read(draftPersistenceMessageProvider.notifier)
          .set('草稿已保存，但自动备份失败，将在后续编辑时重试。');
      _scheduleSnapshot(const Duration(minutes: 1));
      return false;
    }
  }

  void _scheduleSnapshot(Duration delay) {
    if (!_snapshotDirty || _snapshotTimer?.isActive == true) return;
    _snapshotTimer = Timer(delay, () {
      _snapshotTimer = null;
      unawaited(_createDraftSnapshotIfDue());
    });
  }
}

class MappingDraftNotifier extends Notifier<MappingDraft> {
  bool _disposed = false;
  int _writeRevision = 0;

  @override
  MappingDraft build() {
    ref.onDispose(() => _disposed = true);
    return ref.read(initialMappingDraftProvider);
  }

  /// Saves [draft] and drops the previous conversion.
  ///
  /// Does not run conversion. An unchanged draft is ignored.
  void updateMapping(MappingDraft draft) {
    if (_sameDraft(state, draft)) {
      return;
    }
    state = _copyDraft(draft);
    _clearConversion();
    final validation = state.validate();
    if (validation.isValid) {
      _observeWrite(
        ref.read(mappingPersistenceProvider).save(validation.mapping!),
        '保存键盘映射失败，当前修改只在本次运行中有效。',
      );
    }
  }

  /// Restores the built-in mapping and drops the previous conversion.
  void restoreDefault() {
    final defaults = MappingDraft.fromMapping(const KeyboardMapping());
    if (!_sameDraft(state, defaults)) {
      state = defaults;
    }
    _clearConversion();
    _observeWrite(
      ref.read(mappingPersistenceProvider).clear(),
      '恢复默认键位失败，重启后可能恢复原来的键位。',
    );
  }

  void _observeWrite(Future<void> write, String failureMessage) {
    final revision = ++_writeRevision;
    unawaited(_finishWrite(write, revision, failureMessage));
  }

  Future<void> _finishWrite(
    Future<void> write,
    int revision,
    String failureMessage,
  ) async {
    try {
      await write;
      if (!_disposed && revision == _writeRevision) {
        ref.read(mappingPersistenceMessageProvider.notifier).clear();
      }
    } on Object {
      if (!_disposed && revision == _writeRevision) {
        ref
            .read(mappingPersistenceMessageProvider.notifier)
            .set(failureMessage);
      }
    }
  }

  void _clearConversion() {
    ref.read(conversionResultProvider.notifier).clear();
    ref.read(mappingDraftErrorsProvider.notifier).clear();
  }
}

class MappingDraftErrorNotifier extends Notifier<List<MappingDraftError>> {
  @override
  List<MappingDraftError> build() => const [];

  void setErrors(List<MappingDraftError> errors) {
    state = List.unmodifiable(errors);
  }

  void clear() {
    state = const [];
  }
}

class MappingPersistenceMessageNotifier extends Notifier<String?> {
  @override
  String? build() => ref.read(initialMappingPersistenceMessageProvider);

  void set(String message) => state = message;

  void clear() => state = null;
}

class DraftPersistenceMessageNotifier extends Notifier<String?> {
  @override
  String? build() => ref.read(initialDraftPersistenceMessageProvider);

  void set(String message) => state = message;

  void clear() => state = null;
}

class DraftStorageHealthNotifier extends StorageHealthNotifier {
  @override
  StorageHealth build() => ref.read(initialDraftStorageHealthProvider);
}

class DraftWriteStateNotifier extends PersistenceWriteStateNotifier {}

class ConversionResultNotifier extends Notifier<ConversionResult?> {
  @override
  ConversionResult? build() => null;

  /// Validates the mapping draft, then runs the conversion pipeline.
  ///
  /// An illegal draft clears the result and records [mappingDraftErrorsProvider].
  /// It does not parse the score. Duplicate-key warnings are kept on the result.
  void convert() {
    final validation = ref.read(mappingDraftProvider).validate();
    if (!validation.isValid) {
      ref
          .read(mappingDraftErrorsProvider.notifier)
          .setErrors(validation.errors);
      state = null;
      return;
    }

    ref.read(mappingDraftErrorsProvider.notifier).clear();
    final input = ref.read(converterInputProvider);
    final base = ref.read(jianpuConverterProvider);
    final converted = JianpuConverter(
      parser: base.parser,
      lyricAlignment: base.lyricAlignment,
      validator: base.validator,
      mapping: validation.mapping!,
      renderer: base.renderer,
    ).convert(
      scoreText: input.scoreText,
      lyricsText: input.lyricsText,
    );
    state = ConversionResult(
      output: converted.output,
      errors: converted.errors,
      warnings: [
        ...converted.warnings,
        for (final warning in validation.warnings)
          ValidationMessage(line: 0, message: warning.message),
      ],
      unmatchedLyrics: converted.unmatchedLyrics,
      unmatchedLyricTokens: converted.unmatchedLyricTokens,
      missingLyricNotePositions: converted.missingLyricNotePositions,
      score: converted.score,
    );
  }

  void clear() {
    state = null;
  }

  void setResult(ConversionResult result) {
    state = result;
  }
}

final converterInputProvider =
    NotifierProvider<ConverterInputNotifier, ConverterInput>(
  ConverterInputNotifier.new,
);

final converterDraftPersistenceProvider = Provider<ConverterDraftPersistence>(
  (ref) => ConverterDraftPersistence(),
);

final draftSnapshotIntervalProvider = Provider<Duration>(
  (ref) => const Duration(minutes: 5),
);

final draftSaveDelayProvider = Provider<Duration>(
  (ref) => const Duration(seconds: 1),
);

final initialConverterInputProvider = Provider<ConverterInput>(
  (ref) => const ConverterInput(),
);

class SongTitleNotifier extends Notifier<String> {
  @override
  String build() => ref.read(initialSongTitleProvider);

  void update(String value) {
    if (state == value) return;
    state = value;
    ref.read(converterInputProvider.notifier).saveCurrentDraftSoon();
  }

  void replace(String value) => state = value;
}

final initialSongTitleProvider = Provider<String>((ref) => '');

final songTitleProvider = NotifierProvider<SongTitleNotifier, String>(
  SongTitleNotifier.new,
);

final initialDraftPersistenceMessageProvider = Provider<String?>((ref) => null);

final initialDraftStorageHealthProvider = Provider<StorageHealth>(
  (ref) => const StorageHealth(status: PersistenceLoadStatus.missing),
);

final draftStorageHealthProvider =
    NotifierProvider<DraftStorageHealthNotifier, StorageHealth>(
  DraftStorageHealthNotifier.new,
);

final draftWriteStateProvider =
    NotifierProvider<DraftWriteStateNotifier, PersistenceWriteState>(
  DraftWriteStateNotifier.new,
);

final initialDraftRestoredProvider = Provider<bool>((ref) => false);
final initialCurrentSongIdProvider = Provider<String?>((ref) => null);
final initialSmartGridDocumentProvider = Provider<SmartGridDocument>(
  (ref) => SmartGridDocument.empty(),
);

enum ConverterEditorMode { grid, text }

final initialEditorModeProvider = Provider<ConverterEditorMode>(
  (ref) => ConverterEditorMode.text,
);

class EditorModeNotifier extends Notifier<ConverterEditorMode> {
  @override
  ConverterEditorMode build() => ref.read(initialEditorModeProvider);
  void set(ConverterEditorMode mode) => state = mode;
}

final editorModeProvider =
    NotifierProvider<EditorModeNotifier, ConverterEditorMode>(
  EditorModeNotifier.new,
);

class SmartGridDocumentNotifier extends Notifier<SmartGridDocument> {
  @override
  SmartGridDocument build() => ref.read(initialSmartGridDocumentProvider);

  void update(SmartGridDocument document) {
    state = document;
    ref
        .read(converterInputProvider.notifier)
        .replace(const SmartGridCodec().exportInput(document));
  }

  void replaceWithoutInput(SmartGridDocument document) => state = document;

  void updateViewState(SmartGridDocument document) {
    state = document;
    ref.read(converterInputProvider.notifier).saveCurrentDraftSoon();
  }

  void clear() => state = SmartGridDocument.empty();
}

final smartGridDocumentProvider =
    NotifierProvider<SmartGridDocumentNotifier, SmartGridDocument>(
  SmartGridDocumentNotifier.new,
);

class CurrentSongIdNotifier extends Notifier<String?> {
  @override
  String? build() => ref.read(initialCurrentSongIdProvider);
  void set(String? songId) => state = songId;
}

final currentSongIdProvider =
    NotifierProvider<CurrentSongIdNotifier, String?>(CurrentSongIdNotifier.new);

final draftPersistenceMessageProvider =
    NotifierProvider<DraftPersistenceMessageNotifier, String?>(
  DraftPersistenceMessageNotifier.new,
);

final mappingDraftProvider =
    NotifierProvider<MappingDraftNotifier, MappingDraft>(
  MappingDraftNotifier.new,
);

final mappingPersistenceProvider = Provider<MappingPersistence>((ref) {
  return MappingPersistence(SharedPreferencesMappingStorage());
});

final initialMappingDraftProvider = Provider<MappingDraft>((ref) {
  return MappingDraft.fromMapping(const KeyboardMapping());
});

final initialMappingPersistenceMessageProvider =
    Provider<String?>((ref) => null);

final mappingPersistenceMessageProvider =
    NotifierProvider<MappingPersistenceMessageNotifier, String?>(
  MappingPersistenceMessageNotifier.new,
);

final mappingDraftErrorsProvider =
    NotifierProvider<MappingDraftErrorNotifier, List<MappingDraftError>>(
  MappingDraftErrorNotifier.new,
);

final jianpuConverterProvider = Provider<JianpuConverter>((ref) {
  return const JianpuConverter();
});

final conversionResultProvider =
    NotifierProvider<ConversionResultNotifier, ConversionResult?>(
  ConversionResultNotifier.new,
);

MappingDraft _copyDraft(MappingDraft draft) {
  return MappingDraft(
    low: _copyGroup(draft.low),
    middle: _copyGroup(draft.middle),
    high: _copyGroup(draft.high),
  );
}

List<String>? _copyGroup(List<String>? keys) {
  if (keys == null) {
    return null;
  }
  return List<String>.of(keys);
}

bool _sameDraft(MappingDraft left, MappingDraft right) {
  return _sameGroup(left.low, right.low) &&
      _sameGroup(left.middle, right.middle) &&
      _sameGroup(left.high, right.high);
}

bool _sameGroup(List<String>? left, List<String>? right) {
  if (identical(left, right)) {
    return true;
  }
  if (left == null || right == null || left.length != right.length) {
    return false;
  }
  for (var index = 0; index < left.length; index++) {
    if (left[index] != right[index]) {
      return false;
    }
  }
  return true;
}
