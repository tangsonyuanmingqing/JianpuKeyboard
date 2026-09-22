import 'package:flutter_test/flutter_test.dart';
import 'package:jianpu_keyboard/features/converter/png_export_service.dart';

void main() {
  test('creates the agreed timestamped PNG filename', () {
    expect(
      suggestedPngFilename(DateTime(2026, 9, 22, 8, 3, 5)),
      'jianpu-keyboard-20260922-080305.png',
    );
  });
}
