import 'dart:io';

import 'package:integration_test/integration_test_driver.dart';

Future<void> main() => integrationDriver(
      writeResponseOnFailure: true,
      responseDataCallback: (data) => writeResponseData(
        data,
        testOutputFilename: 'table_scroll_native_'
            '${Platform.environment['UI_SCROLL_RUN'] ?? DateTime.now().millisecondsSinceEpoch}',
        destinationDirectory: 'build/performance',
      ),
    );
