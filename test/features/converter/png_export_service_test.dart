import 'package:flutter_test/flutter_test.dart';
import 'package:jianpu_keyboard/features/converter/png_export_service.dart';

void main() {
  test('creates the agreed timestamped PNG filename', () {
    expect(
      suggestedPngFilename(DateTime(2026, 9, 22, 8, 3, 5)),
      'jianpu-keyboard-20260922-080305.png',
    );
  });

  test('uses a safe song title and image type when both are provided', () {
    expect(
      suggestedPngFilename(
        DateTime(2026, 9, 22, 8, 3, 5),
        songTitle: '晨光：练习版',
        imageType: '字母简谱',
      ),
      '晨光-练习版-字母简谱-20260922-080305.png',
    );
  });
}
