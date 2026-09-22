import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/converter/jianpu_converter.dart';
import '../../core/mapping/keyboard_mapping.dart';
import '../../core/mapping/mapping_draft.dart';
import '../../core/models/conversion_result.dart';
import '../../core/models/validation_message.dart';
import '../../infrastructure/shared_preferences_mapping_storage.dart';
import 'mapping_persistence.dart';

class ConverterInput {
  final String scoreText;
  final String lyricsText;

  const ConverterInput({
    this.scoreText = '',
    this.lyricsText = '',
  });

  @override
  bool operator ==(Object other) {
    return other is ConverterInput &&
        other.scoreText == scoreText &&
        other.lyricsText == lyricsText;
  }

  @override
  int get hashCode => Object.hash(scoreText, lyricsText);
}

class ConverterInputNotifier extends Notifier<ConverterInput> {
  @override
  ConverterInput build() => const ConverterInput();

  void setScoreText(String value) {
    if (state.scoreText == value) {
      return;
    }
    state = ConverterInput(scoreText: value, lyricsText: state.lyricsText);
    ref.read(conversionResultProvider.notifier).clear();
  }

  void setLyricsText(String value) {
    if (state.lyricsText == value) {
      return;
    }
    state = ConverterInput(scoreText: state.scoreText, lyricsText: value);
    ref.read(conversionResultProvider.notifier).clear();
  }

  void clear() {
    state = const ConverterInput();
    ref.read(conversionResultProvider.notifier).clear();
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
