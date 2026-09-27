import 'package:flutter_test/flutter_test.dart';
import 'package:jianpu_keyboard/features/converter/smart_grid_lyric_tokens.dart';

void main() {
  test('splits Chinese characters while retaining numeric and Latin runs', () {
    expect(splitSmartGridLyricCells('晨光'), ['晨', '光']);
    expect(splitSmartGridLyricCells('520'), ['520']);
    expect(splitSmartGridLyricCells('第520次'), ['第', '520', '次']);
    expect(splitSmartGridLyricCells('hello world'), ['hello', 'world']);
  });

  test('keeps lyric structure symbols in their own cells', () {
    expect(splitSmartGridLyricCells('我//爱|你-'), ['我', '//', '爱', '|', '你', '-']);
  });
}
