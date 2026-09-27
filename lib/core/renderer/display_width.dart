/// Display-cell width used only by the plain-text renderer.
///
/// ASCII and other halfwidth characters occupy 1 cell. CJK and other
/// East-Asian wide characters occupy 2 cells.
int displayWidth(String text) {
  var width = 0;
  for (final rune in text.runes) {
    width += isWideDisplayCharacter(rune) ? 2 : 1;
  }
  return width;
}

/// Whether [rune] should occupy two display cells.
bool isWideDisplayCharacter(int rune) {
  return rune >= 0x1100 && rune <= 0x115F ||
      rune >= 0x2E80 && rune <= 0xA4CF ||
      rune >= 0xAC00 && rune <= 0xD7A3 ||
      rune >= 0xF900 && rune <= 0xFAFF ||
      rune >= 0xFE10 && rune <= 0xFE19 ||
      rune >= 0xFE30 && rune <= 0xFE6F ||
      rune >= 0xFF00 && rune <= 0xFF60 ||
      rune >= 0xFFE0 && rune <= 0xFFE6 ||
      rune >= 0x1F300 && rune <= 0x1F64F ||
      rune >= 0x20000 && rune <= 0x2FFFD ||
      rune >= 0x30000 && rune <= 0x3FFFD;
}

/// Right-pads [text] with spaces until it occupies [width] display cells.
String padToDisplayWidth(String text, int width) {
  final extra = width - displayWidth(text);
  if (extra <= 0) {
    return text;
  }
  return '$text${' ' * extra}';
}

/// Converts ASCII keyboard letters into their fullwidth counterparts.
///
/// A fullwidth Latin letter occupies the same two display cells as one CJK
/// lyric character, which lets the plain-text score centre both contents on
/// the same column axis.
String toFullwidthKeyboardLetters(String text) {
  return String.fromCharCodes(text.runes.map((rune) {
    if (rune >= 0x41 && rune <= 0x5A) return rune + 0xFEE0;
    return rune;
  }));
}

/// Centres [text] inside [width] display cells.
///
/// When one spare display cell cannot be split evenly, it is kept on the
/// right, leaving the text half a cell to the left as documented by the UI.
String centerToDisplayWidth(String text, int width) {
  final extra = width - displayWidth(text);
  if (extra <= 0) return text;
  final left = extra ~/ 2;
  return '${' ' * left}$text${' ' * (extra - left)}';
}

/// Renders cells with their display-width centres aligned and drops only
/// trailing whitespace that has no following column to position.
String renderCenteredDisplayRow(List<String> texts, List<int> widths) {
  assert(texts.length == widths.length);
  return [
    for (var index = 0; index < texts.length; index++)
      centerToDisplayWidth(texts[index], widths[index]),
  ].join(' ').trimRight();
}
