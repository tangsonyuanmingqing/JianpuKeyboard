/// Splits lyrics into the cell-sized units used by the smart grid.
///
/// CJK characters each take one cell. Consecutive digits and Latin word
/// characters stay together so lyrics such as `第520次` become
/// `第 | 520 | 次`.
List<String> splitSmartGridLyricCells(String text) {
  final result = <String>[];
  final runes = text.trim().runes.toList();
  var index = 0;

  while (index < runes.length) {
    final character = String.fromCharCode(runes[index]);
    if (character.trim().isEmpty) {
      index += 1;
      continue;
    }
    if (character == '/' &&
        index + 1 < runes.length &&
        String.fromCharCode(runes[index + 1]) == '/') {
      result.add('//');
      index += 2;
      continue;
    }
    if (character == '|' || character == '-') {
      result.add(character);
      index += 1;
      continue;
    }
    if (_isCjk(runes[index])) {
      result.add(character);
      index += 1;
      continue;
    }
    if (_isDigit(runes[index])) {
      final start = index;
      while (index < runes.length && _isDigit(runes[index])) {
        index += 1;
      }
      result.add(String.fromCharCodes(runes.sublist(start, index)));
      continue;
    }
    if (_isLatinWordCharacter(runes[index])) {
      final start = index;
      while (index < runes.length && _isLatinWordCharacter(runes[index])) {
        index += 1;
      }
      result.add(String.fromCharCodes(runes.sublist(start, index)));
      continue;
    }
    result.add(character);
    index += 1;
  }

  return result;
}

bool isSingleSmartGridCjk(String value) =>
    value.runes.length == 1 && _isCjk(value.runes.single);

bool _isCjk(int rune) =>
    (rune >= 0x3400 && rune <= 0x4dbf) || (rune >= 0x4e00 && rune <= 0x9fff);

bool _isDigit(int rune) => rune >= 0x30 && rune <= 0x39;

bool _isLatinWordCharacter(int rune) =>
    (rune >= 0x41 && rune <= 0x5a) ||
    (rune >= 0x61 && rune <= 0x7a) ||
    rune == 0x2d;
