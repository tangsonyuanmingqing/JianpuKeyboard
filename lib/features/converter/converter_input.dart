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
