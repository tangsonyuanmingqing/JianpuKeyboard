import 'dart:io';

import 'package:integration_test/integration_test_driver.dart';

Future<void> main() => integrationDriver(
      writeResponseOnFailure: true,
      responseDataCallback: (data) => writeResponseData(
        data,
        testOutputFilename:
            'smart_grid_ui_performance_${Platform.environment['UI_PERFORMANCE_RUN'] ?? 'latest'}',
        destinationDirectory: 'build/performance',
      ),
    );
