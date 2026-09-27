import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jianpu_keyboard/app/window/window_pin.dart';

void main() {
  test('starts unpinned and only changes state after native success', () async {
    final platform = _WindowPinPlatformFake();
    final container = ProviderContainer(overrides: [
      windowPinPlatformProvider.overrideWithValue(platform),
    ]);
    addTearDown(container.dispose);

    expect(container.read(windowPinProvider).isPinned, isFalse);

    expect(await container.read(windowPinProvider.notifier).toggle(), isTrue);
    expect(platform.requests, [true]);
    expect(container.read(windowPinProvider).isPinned, isTrue);
  });

  test('keeps the previous state when the native request fails', () async {
    final platform = _WindowPinPlatformFake(fail: true);
    final container = ProviderContainer(overrides: [
      windowPinPlatformProvider.overrideWithValue(platform),
    ]);
    addTearDown(container.dispose);

    expect(await container.read(windowPinProvider.notifier).toggle(), isFalse);
    expect(platform.requests, [true]);
    expect(container.read(windowPinProvider).isPinned, isFalse);
    expect(container.read(windowPinProvider).isUpdating, isFalse);
  });

  test('ignores a second toggle while the first native request is pending',
      () async {
    final completion = Completer<void>();
    final platform = _WindowPinPlatformFake(completion: completion);
    final container = ProviderContainer(overrides: [
      windowPinPlatformProvider.overrideWithValue(platform),
    ]);
    addTearDown(container.dispose);

    final first = container.read(windowPinProvider.notifier).toggle();
    expect(container.read(windowPinProvider).isUpdating, isTrue);
    expect(await container.read(windowPinProvider.notifier).toggle(), isFalse);
    expect(platform.requests, [true]);

    completion.complete();
    expect(await first, isTrue);
    expect(container.read(windowPinProvider).isPinned, isTrue);
  });

  testWidgets('shows status icons and feedback after toggling', (tester) async {
    final platform = _WindowPinPlatformFake();
    await tester.pumpWidget(_Harness(platform: platform));

    expect(find.byTooltip('开启窗口置顶'), findsOneWidget);
    expect(find.byIcon(Icons.push_pin_outlined), findsOneWidget);

    await tester.tap(find.byKey(const Key('window-pin-toggle-button')));
    await tester.pumpAndSettle();

    expect(find.byTooltip('取消窗口置顶'), findsOneWidget);
    expect(find.byIcon(Icons.push_pin), findsOneWidget);
    expect(find.text('已开启窗口置顶'), findsOneWidget);
  });

  testWidgets('reports failure without changing the visible state',
      (tester) async {
    final platform = _WindowPinPlatformFake(fail: true);
    await tester.pumpWidget(_Harness(platform: platform));

    await tester.tap(find.byKey(const Key('window-pin-toggle-button')));
    await tester.pumpAndSettle();

    expect(find.byTooltip('开启窗口置顶'), findsOneWidget);
    expect(find.text('窗口置顶设置失败，请重试'), findsOneWidget);
  });

  testWidgets('does not render on unsupported platforms', (tester) async {
    await tester.pumpWidget(
      _Harness(platform: _WindowPinPlatformFake(isSupported: false)),
    );

    expect(find.byKey(const Key('window-pin-toggle-button')), findsNothing);
  });
}

class _Harness extends StatelessWidget {
  const _Harness({required this.platform});

  final WindowPinPlatform platform;

  @override
  Widget build(BuildContext context) {
    return ProviderScope(
      overrides: [windowPinPlatformProvider.overrideWithValue(platform)],
      child: MaterialApp(
        home: Scaffold(
          appBar: AppBar(actions: const [WindowPinToggleButton()]),
          body: const SizedBox(),
        ),
      ),
    );
  }
}

class _WindowPinPlatformFake extends WindowPinPlatform {
  _WindowPinPlatformFake({
    this.isSupported = true,
    this.fail = false,
    this.completion,
  });

  @override
  final bool isSupported;
  final bool fail;
  final Completer<void>? completion;
  final List<bool> requests = [];

  @override
  Future<void> setAlwaysOnTop(bool enabled) async {
    requests.add(enabled);
    if (completion != null) {
      await completion!.future;
    }
    if (fail) {
      throw Exception('native failure');
    }
  }
}
