import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jianpu_keyboard/features/converter/semicolon_line_break_formatter.dart';

void main() {
  const formatter = SemicolonLineBreakFormatter();

  TextEditingValue value(String text, {int? cursor}) => TextEditingValue(
        text: text,
        selection: TextSelection.collapsed(offset: cursor ?? text.length),
      );

  test('adds a row separator before a typed line break', () {
    final result = formatter.formatEditUpdate(value('3 4 5'), value('3 4 5\n'));

    expect(result.text, '3 4 5;\n');
    expect(result.selection.baseOffset, 7);
  });

  test('does not add another separator after one or after a header', () {
    expect(
      formatter.formatEditUpdate(value('3 4;'), value('3 4;\n')).text,
      '3 4;\n',
    );
    expect(
      formatter.formatEditUpdate(value('[谱]'), value('[谱]\n')).text,
      '[谱]\n',
    );
  });

  test('keeps pasted multi-line text unchanged', () {
    final result = formatter.formatEditUpdate(value(''), value('3 4\n5 6'));

    expect(result.text, '3 4\n5 6');
  });
}
