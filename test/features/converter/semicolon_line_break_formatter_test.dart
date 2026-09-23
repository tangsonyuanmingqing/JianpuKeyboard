import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jianpu_keyboard/features/converter/semicolon_line_break_formatter.dart';

void main() {
  const formatter = SemicolonLineBreakFormatter();

  test('adds a visible semicolon before a Windows Enter line break', () {
    const oldValue = TextEditingValue(
      text: '3 4 5',
      selection: TextSelection.collapsed(offset: 5),
    );
    const newValue = TextEditingValue(
      text: '3 4 5\r\n',
      selection: TextSelection.collapsed(offset: 7),
    );

    final formatted = formatter.formatEditUpdate(oldValue, newValue);

    expect(formatted.text, '3 4 5;\r\n');
    expect(formatted.selection.baseOffset, 8);
  });

  test('keeps one visible semicolon before a Unix Enter line break', () {
    const oldValue = TextEditingValue(
      text: '3 4 5',
      selection: TextSelection.collapsed(offset: 5),
    );
    const newValue = TextEditingValue(
      text: '3 4 5\n',
      selection: TextSelection.collapsed(offset: 6),
    );

    final formatted = formatter.formatEditUpdate(oldValue, newValue);

    expect(formatted.text, '3 4 5;\n');
    expect(formatted.selection.baseOffset, 7);
  });

  test('adds a semicolon when Enter normalizes a middle Windows line break',
      () {
    const oldValue = TextEditingValue(
      text: '3 4 5\r\n[词] 我爱',
      selection: TextSelection.collapsed(offset: 5),
    );
    const newValue = TextEditingValue(
      text: '3 4 5\n\n[词] 我爱',
      selection: TextSelection.collapsed(offset: 6),
    );

    final formatted = formatter.formatEditUpdate(oldValue, newValue);

    expect(formatted.text, '3 4 5;\n\n[词] 我爱');
    expect(formatted.selection.baseOffset, 7);
  });
}
