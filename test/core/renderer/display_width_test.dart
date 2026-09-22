import 'package:flutter_test/flutter_test.dart';
import 'package:jianpu_keyboard/core/renderer/display_width.dart';

void main() {
  test('counts ASCII characters as width 1', () {
    expect(displayWidth('D'), 1);
    expect(displayWidth('0'), 1);
    expect(displayWidth('-'), 1);
    expect(displayWidth('|'), 1);
    expect(displayWidth('S -'), 3);
  });

  test('counts CJK characters as width 2', () {
    expect(displayWidth('我'), 2);
    expect(displayWidth('低'), 2);
    expect(displayWidth('垂'), 2);
  });

  test('does not use String.length for mixed CJK and ASCII', () {
    expect('我D'.length, 2);
    expect(displayWidth('我D'), 3);
  });

  test('pads ASCII up to a CJK column width', () {
    expect(padToDisplayWidth('D', 2), 'D ');
    expect(padToDisplayWidth('我', 2), '我');
    expect(padToDisplayWidth('', 1), ' ');
  });
}
