import 'package:flutter_test/flutter_test.dart';
import 'package:jianpu_keyboard/features/converter/song_output_formatter.dart';

void main() {
  test('adds a song title above copied notation', () {
    expect(formatSongOutput('晨光', 'D F G'), '晨光\n\nD F G');
  });

  test('keeps copied notation unchanged without a song title', () {
    expect(formatSongOutput('', 'D F G'), 'D F G');
  });
}
