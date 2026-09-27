import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jianpu_keyboard/features/converter/table_scroll_frame.dart';

import '../../support/table_scroll_test_helpers.dart';

const _frameKey = Key('frame-harness');
final _windows = TargetPlatformVariant.only(TargetPlatform.windows);

void main() {
  testWidgets('private rail metrics do not duplicate notifications to the page',
      (tester) async {
    final notifications = <ScrollMetricsNotification>[];
    await tester.pumpWidget(NotificationListener<ScrollMetricsNotification>(
        onNotification: (notification) {
          notifications.add(notification);
          return false;
        },
        child: _app()));
    await tester.pumpAndSettle();
    expect(notifications.where((n) => n.metrics.axis == Axis.horizontal),
        hasLength(1));
    expect(notifications.where((n) => n.metrics.axis == Axis.vertical),
        hasLength(1));
    await tester.pumpWidget(const SizedBox.shrink());
  }, variant: _windows);

  for (final axes in [
    (false, false),
    (true, false),
    (false, true),
    (true, true)
  ]) {
    testWidgets('painted thumbs reflect overflow $axes with fixed gutters',
        (tester) async {
      await tester.pumpWidget(_app(
        width: axes.$1 ? 700 : 100,
        height: axes.$2 ? 600 : 40,
      ));
      await tester.pumpAndSettle();
      final frame = find.byKey(_frameKey);
      expect(tableThumb(tester, frame, Axis.horizontal) != null, axes.$1);
      expect(tableThumb(tester, frame, Axis.vertical) != null, axes.$2);
      expect(tester.getSize(find.byKey(const Key('content-viewport'))),
          const Size(296, 176));
      expect(find.descendant(of: frame, matching: find.byType(RawScrollbar)),
          findsNWidgets(2));
      expect(find.descendant(of: frame, matching: find.byType(Scrollbar)),
          findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());
    }, variant: _windows);
  }

  for (final axis in Axis.values) {
    testWidgets(
        '$axis thumb, track and outside release control only their axis',
        (tester) async {
      await tester.pumpWidget(_app());
      await tester.pumpAndSettle();
      final state = tester.state<_HarnessState>(find.byType(_Harness));
      final controller =
          axis == Axis.horizontal ? state.horizontal : state.vertical;
      final other = axis == Axis.horizontal ? state.vertical : state.horizontal;
      final frame = find.byKey(_frameKey);
      final start = tableThumb(tester, frame, axis)!;
      final mouse =
          await tester.startGesture(start, kind: PointerDeviceKind.mouse);
      await mouse.moveBy(axis == Axis.horizontal
          ? const Offset(800, 0)
          : const Offset(0, 800));
      await tester.pump();
      await mouse.up();
      await tester.pumpAndSettle();
      expect(
          controller.offset, closeTo(controller.position.maxScrollExtent, .5));
      expect(other.offset, 0);
      final end = tableThumb(tester, frame, axis)!;
      final back =
          await tester.startGesture(end, kind: PointerDeviceKind.mouse);
      await back.moveBy(axis == Axis.horizontal
          ? const Offset(-800, 0)
          : const Offset(0, -800));
      await tester.pump();
      await back.up();
      await tester.pumpAndSettle();
      expect(controller.offset, closeTo(0, .5));
      final bounds = tester.getRect(frame);
      final track = axis == Axis.horizontal
          ? Offset(bounds.right - 40, bounds.bottom - 12)
          : Offset(bounds.right - 12, bounds.bottom - 40);
      await tester.tapAt(track, kind: PointerDeviceKind.mouse);
      await tester.pump(const Duration(milliseconds: 120));
      await tester.pumpAndSettle();
      expect(controller.offset, greaterThan(0));
      expect(other.offset, 0);
      final before = controller.offset;
      final cancelled = await tester.startGesture(
          tableThumb(tester, frame, axis)!,
          kind: PointerDeviceKind.mouse);
      await cancelled.moveBy(axis == Axis.horizontal
          ? const Offset(-20, 0)
          : const Offset(0, -20));
      await tester.pump();
      expect(controller.offset, lessThan(before));
      await cancelled.cancel();
      await tester.pumpAndSettle();
      final afterCancel = controller.offset;
      await tester.tapAt(bounds.center, kind: PointerDeviceKind.mouse);
      expect(controller.offset, afterCancel);
      await tester.pumpWidget(const SizedBox.shrink());
      expect(tester.takeException(), isNull);
    }, variant: _windows);
  }

  testWidgets('dimensions and contents update thumbs without rebuilding layout',
      (tester) async {
    await tester.pumpWidget(_app(width: 100, height: 40));
    await tester.pumpAndSettle();
    final frame = find.byKey(_frameKey);
    expect(tableThumb(tester, frame, Axis.horizontal), isNull);
    await tester.pumpWidget(_app());
    await tester.pumpAndSettle();
    expect(tableThumb(tester, frame, Axis.horizontal), isNotNull);
    expect(tableThumb(tester, frame, Axis.vertical), isNotNull);
    await dragTableThumb(tester, frame, Axis.horizontal, const Offset(800, 0));
    await tester.pumpWidget(_app(width: 100, height: 40));
    await tester.pumpAndSettle();
    expect(tableThumb(tester, frame, Axis.horizontal), isNull);
    expect(tableThumb(tester, frame, Axis.vertical), isNull);
    final state = tester.state<_HarnessState>(find.byType(_Harness));
    expect(state.horizontal.offset, 0);
    expect(tester.getSize(find.byKey(const Key('content-viewport'))),
        const Size(296, 176));
    await tester.pumpWidget(const SizedBox.shrink());
  }, variant: _windows);

  testWidgets('nested horizontal metrics cannot replace table thumb geometry',
      (tester) async {
    await tester.pumpWidget(_app(nested: true));
    await tester.pumpAndSettle();
    final state = tester.state<_HarnessState>(find.byType(_Harness));
    final frame = find.byKey(_frameKey);
    final before = tableThumb(tester, frame, Axis.horizontal);
    state.nested.jumpTo(200);
    await tester.pumpAndSettle();
    expect(state.horizontal.offset, 0);
    expect(tableThumb(tester, frame, Axis.horizontal), before);
    await tester.pumpWidget(_app(nested: true, nestedWidth: 40));
    await tester.pumpAndSettle();
    expect(tableThumb(tester, frame, Axis.horizontal), before);
    await dragTableThumb(tester, frame, Axis.horizontal, const Offset(80, 0));
    expect(state.horizontal.offset, greaterThan(0));
    await tester.pumpWidget(const SizedBox.shrink());
  }, variant: _windows);
}

Widget _app(
        {double width = 700,
        double height = 600,
        bool nested = false,
        double nestedWidth = 700}) =>
    MaterialApp(
        home: Scaffold(
            body: Center(
                child: _Harness(
                    width: width,
                    height: height,
                    nested: nested,
                    nestedWidth: nestedWidth))));

class _Harness extends StatefulWidget {
  const _Harness(
      {required this.width,
      required this.height,
      required this.nested,
      required this.nestedWidth});
  final double width;
  final double height;
  final bool nested;
  final double nestedWidth;
  @override
  State<_Harness> createState() => _HarnessState();
}

class _HarnessState extends State<_Harness> {
  final horizontal = ScrollController();
  final vertical = ScrollController();
  final nested = ScrollController();
  @override
  void dispose() {
    horizontal.dispose();
    vertical.dispose();
    nested.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => SizedBox(
      key: _frameKey,
      width: 320,
      height: 200,
      child: TableScrollFrame(
          horizontalController: horizontal,
          verticalController: vertical,
          headerHeight: 30,
          child: SizedBox(
              key: const Key('content-viewport'),
              child: SingleChildScrollView(
                  controller: horizontal,
                  scrollDirection: Axis.horizontal,
                  child: SizedBox(
                      width: widget.width,
                      child: Column(children: [
                        const SizedBox(height: 30),
                        Expanded(
                            child: SingleChildScrollView(
                                controller: vertical,
                                child: SizedBox(
                                    height: widget.height,
                                    child: widget.nested
                                        ? Align(
                                            alignment: Alignment.topLeft,
                                            child: SizedBox(
                                                width: 100,
                                                height: 40,
                                                child: SingleChildScrollView(
                                                    controller: nested,
                                                    scrollDirection:
                                                        Axis.horizontal,
                                                    child: SizedBox(
                                                        width:
                                                            widget.nestedWidth,
                                                        height: 40))))
                                        : const SizedBox())))
                      ]))))));
}
