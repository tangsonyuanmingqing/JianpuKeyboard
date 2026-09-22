import 'package:flutter/services.dart';

import '../../core/syntax/jianpu_syntax.dart';

/// Stores an explicit row separator when the user presses Enter while typing.
/// Pasted multi-line text remains untouched for backward compatibility.
class SemicolonLineBreakFormatter extends TextInputFormatter {
  const SemicolonLineBreakFormatter();

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    if (newValue.text.length != oldValue.text.length + 1) return newValue;

    final insertion = _insertionIndex(oldValue.text, newValue.text);
    if (insertion == null || newValue.text[insertion] != '\n') return newValue;

    final lineStart = newValue.text.lastIndexOf('\n', insertion - 1) + 1;
    final line = newValue.text.substring(lineStart, insertion).trimRight();
    if (line.isEmpty ||
        line == JianpuSyntax.scoreHeader ||
        line == JianpuSyntax.lyricsHeader ||
        line.endsWith(JianpuSyntax.rowSeparator)) {
      return newValue;
    }

    final text =
        '${newValue.text.substring(0, insertion)}${JianpuSyntax.rowSeparator}'
        '${newValue.text.substring(insertion)}';
    return newValue.copyWith(
      text: text,
      selection: TextSelection.collapsed(offset: newValue.selection.end + 1),
    );
  }

  int? _insertionIndex(String oldText, String newText) {
    for (var index = 0; index < oldText.length; index++) {
      if (oldText[index] != newText[index]) return index;
    }
    return oldText.length;
  }
}
