import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/converter/jianpu_converter.dart';
import '../../core/models/conversion_result.dart';

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

class ConversionResultNotifier extends Notifier<ConversionResult?> {
  @override
  ConversionResult? build() => null;

  void convert() {
    final input = ref.read(converterInputProvider);
    state = ref.read(jianpuConverterProvider).convert(
          scoreText: input.scoreText,
          lyricsText: input.lyricsText,
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

final jianpuConverterProvider = Provider<JianpuConverter>((ref) {
  return const JianpuConverter();
});

final conversionResultProvider =
    NotifierProvider<ConversionResultNotifier, ConversionResult?>(
  ConversionResultNotifier.new,
);
