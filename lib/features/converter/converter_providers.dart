import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/converter/jianpu_converter.dart';
import '../../core/mapping/keyboard_mapping.dart';
import '../../core/mapping/mapping_draft.dart';
import '../../core/models/conversion_result.dart';
import '../../core/models/validation_message.dart';
import '../../infrastructure/shared_preferences_mapping_storage.dart';
import 'converter_input.dart';
import 'converter_draft_persistence.dart';
import 'mapping_persistence.dart';

class ConverterInputNotifier extends Notifier<ConverterInput> {
  Timer? _saveTimer;

  @override
  ConverterInput build() {
    ref.onDispose(() => _saveTimer?.cancel());
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
    state = const ConverterInput();
    ref.read(conversionResultProvider.notifier).clear();
    unawaited(_clearSavedDraft());
    return previous;
  }

  void restore(ConverterInput input) {
    _replace(input, saveImmediately: true);
  }

  void replace(ConverterInput input) => _replace(input);

  void _replace(ConverterInput input, {bool saveImmediately = false}) {
    state = input;
    ref.read(conversionResultProvider.notifier).clear();
    _saveTimer?.cancel();
    if (saveImmediately) {
      unawaited(_saveDraft(input));
      return;
    }
    _saveTimer = Timer(const Duration(seconds: 1), () {
      unawaited(_saveDraft(input));
    });
  }

  Future<void> _saveDraft(ConverterInput input) async {
    try {
      await ref.read(converterDraftPersistenceProvider).save(input);
      ref.read(draftPersistenceMessageProvider.notifier).clear();
    } on Object {
      ref
          .read(draftPersistenceMessageProvider.notifier)
          .set('保存草稿失败，本次编辑可能无法在重启后恢复。');
    }
  }

  Future<void> _clearSavedDraft() async {
    try {
      await ref.read(converterDraftPersistenceProvider).clear();
      ref.read(draftPersistenceMessageProvider.notifier).clear();
    } on Object {
      ref
          .read(draftPersistenceMessageProvider.notifier)
          .set('清除草稿失败，重启后可能恢复原来的内容。');
    }
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
}

final converterInputProvider =
    NotifierProvider<ConverterInputNotifier, ConverterInput>(
  ConverterInputNotifier.new,
);

final converterDraftPersistenceProvider = Provider<ConverterDraftPersistence>(
  (ref) => ConverterDraftPersistence(),
);

final initialConverterInputProvider = Provider<ConverterInput>(
  (ref) => const ConverterInput(),
);

final initialDraftPersistenceMessageProvider = Provider<String?>((ref) => null);

final initialDraftRestoredProvider = Provider<bool>((ref) => false);

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
