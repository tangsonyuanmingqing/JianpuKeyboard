import 'dart:async';
import 'dart:ui' show AppExitResponse;

import 'package:flutter_test/flutter_test.dart';
import 'package:jianpu_keyboard/app/app.dart';

void main() {
  test('waits for the latest flush before allowing exit', () async {
    final flush = Completer<void>();
    var completed = false;

    final response = handleAppExitRequest(
      flush: () => flush.future,
      onFailure: () {},
    )..then((_) => completed = true);
    await Future<void>.delayed(Duration.zero);
    expect(completed, false);

    flush.complete();
    expect(await response, AppExitResponse.exit);
    expect(completed, true);
  });

  test('cancels exit and reports a failed flush', () async {
    var failureReported = false;

    final response = await handleAppExitRequest(
      flush: () async => throw StateError('write failed'),
      onFailure: () => failureReported = true,
    );

    expect(response, AppExitResponse.cancel);
    expect(failureReported, true);
  });
}
