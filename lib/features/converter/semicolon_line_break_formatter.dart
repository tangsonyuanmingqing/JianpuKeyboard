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
    final insertion = _enteredLineBreakAtCursor(oldValue, newValue);
    if (insertion == null) return newValue;

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

  int? _enteredLineBreakAtCursor(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final selection = oldValue.selection;
    if (!selection.isValid || !selection.isCollapsed) {
      return null;
    }

    final insertion = selection.baseOffset;
    if (insertion > oldValue.text.length || insertion > newValue.text.length) {
      return null;
    }
    if (oldValue.text.substring(0, insertion) !=
        newValue.text.substring(0, insertion)) {
      return null;
    }

    final oldTail = oldValue.text.substring(insertion);
    final newTail = newValue.text.substring(insertion);
    final lineBreakLength = _leadingLineBreakLength(newTail);
    if (lineBreakLength == null) return null;

    final remainingNewTail = newTail.substring(lineBreakLength);
    if (_normalizeLineBreaks(remainingNewTail) !=
        _normalizeLineBreaks(oldTail)) {
      return null;
    }

    return insertion;
  }

  int? _leadingLineBreakLength(String value) {
    if (value.startsWith('\r\n')) return 2;
    if (value.startsWith('\n')) return 1;
    return null;
  }

  String _normalizeLineBreaks(String value) => value.replaceAll('\r\n', '\n');
}
