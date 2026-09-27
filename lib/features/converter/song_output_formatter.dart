String formatSongOutput(String title, String output) {
  final normalizedTitle = title.trim();
  return normalizedTitle.isEmpty ? output : '$normalizedTitle\n\n$output';
}
