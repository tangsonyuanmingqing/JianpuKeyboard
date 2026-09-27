import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import '../test/features/converter/table_scroll_interaction_test.dart'
    as interaction;
import '../test/features/library/song_library_scroll_test.dart' as song_library;

/// Run the same painted-thumb regressions in a native window, with native view
/// dimensions. Framework IME injection is not a physical Windows IME test.
void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  binding.reportData = {
    'recorded_at': DateTime.now().toUtc().toIso8601String(),
    'platform': Platform.operatingSystem,
    'cases': 5,
    'coverage': 'input/output/library painted rails, drag, track, ends, '
        'outside release, cancellation, focus, injected composition and undo',
    'physical_ime_tested': false,
  };
  setUp(() {
    expect(Platform.isWindows, isTrue);
    binding.testTextInput.register();
  });
  tearDown(binding.testTextInput.unregister);
  interaction.main(native: true);
  song_library.main(native: true);
  tearDownAll(() {
    binding.reportData!['passed'] = binding.failureMethodsDetails.isEmpty;
    binding.reportData!['results'] = binding.results
        .map((name, result) => MapEntry(name, result.toString()));
    final view = binding.platformDispatcher.views.first;
    binding.reportData!['physical_width'] = view.physicalSize.width;
    binding.reportData!['physical_height'] = view.physicalSize.height;
    binding.reportData!['device_pixel_ratio'] = view.devicePixelRatio;
  });
}
