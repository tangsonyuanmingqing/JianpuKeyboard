import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/converter/jianpu_converter.dart';
import '../../core/mapping/keyboard_mapping.dart';
import '../../core/mapping/mapping_draft.dart';
import '../../core/models/conversion_result.dart';
import '../../core/models/validation_message.dart';

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
  @override
  MappingDraft build() => MappingDraft.fromMapping(const KeyboardMapping());

  /// Saves [draft] and drops the previous conversion.
  ///
  /// Does not run conversion. An unchanged draft is ignored.
  void updateMapping(MappingDraft draft) {
    if (_sameDraft(state, draft)) {
      return;
    }
    state = _copyDraft(draft);
    _clearConversion();
  }

  /// Restores the built-in mapping and drops the previous conversion.
  void restoreDefault() {
    final defaults = MappingDraft.fromMapping(const KeyboardMapping());
    if (!_sameDraft(state, defaults)) {
      state = defaults;
    }
    _clearConversion();
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
