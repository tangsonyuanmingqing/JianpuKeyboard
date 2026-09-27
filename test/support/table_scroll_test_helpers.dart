import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jianpu_keyboard/features/converter/table_scroll_frame.dart';

/// Finds the painted, mouse-hit-testable thumb, not a visibility flag.
Offset? tableThumb(WidgetTester tester, Finder table, Axis axis) {
  final tableRect = tester.getRect(table);
  final paints = find.descendant(of: table, matching: find.byType(CustomPaint));
  for (final element in paints.evaluate()) {
    final paint = element.widget as CustomPaint;
    final painter = paint.foregroundPainter;
    if (painter is! ScrollbarPainter) continue;
    final target = find.byElementPredicate((candidate) => candidate == element);
    final origin = tester.getTopLeft(target);
    final size = tester.getSize(target);
    for (double cross = 2; cross <= 22; cross += 2) {
      final limit = axis == Axis.horizontal ? size.width : size.height;
      for (double main = 2; main < limit; main += 2) {
        final point = axis == Axis.horizontal
            ? Offset(main, size.height - cross)
            : Offset(size.width - cross, main);
        final global = origin + point;
        final inRail = axis == Axis.horizontal
            ? global.dy >= tableRect.bottom - 24
            : global.dx >= tableRect.right - 24;
        if (inRail &&
            painter.hitTestOnlyThumbInteractive(
                point, PointerDeviceKind.mouse)) {
          return global;
        }
      }
    }
  }
  return null;
}

Future<void> dragTableThumb(
    WidgetTester tester, Finder table, Axis axis, Offset delta) async {
  final start = tableThumb(tester, table, axis);
  expect(start, isNotNull,
      reason: 'The $axis thumb must be painted and hittable.');
  final mouse =
      await tester.startGesture(start!, kind: PointerDeviceKind.mouse);
  await mouse.moveBy(delta);
  await tester.pump();
  await mouse.up();
  await tester.pumpAndSettle();
}

/// Exercises Flutter's painted rails on a real table, including drag capture.
/// Leaves both axes at their origin, ready for subsequent editing/perf checks.
Future<void> exerciseTableScrollbars(WidgetTester tester, Finder table,
    {VoidCallback? verify}) async {
  final frame = tester.widget<TableScrollFrame>(
      find.descendant(of: table, matching: find.byType(TableScrollFrame)));
  expect(find.descendant(of: table, matching: find.byType(RawScrollbar)),
      findsNWidgets(2));
  expect(find.descendant(of: table, matching: find.byType(Scrollbar)),
      findsNothing);
  for (final axis in Axis.values) {
    final controller = axis == Axis.horizontal
        ? frame.horizontalController
        : frame.verticalController;
    final other = axis == Axis.horizontal
        ? frame.verticalController
        : frame.horizontalController;
    expect(controller.position.maxScrollExtent, greaterThan(0));
    final forward =
        axis == Axis.horizontal ? const Offset(4000, 0) : const Offset(0, 4000);
    await dragTableThumb(tester, table, axis, forward);
    expect(controller.offset, closeTo(controller.position.maxScrollExtent, .5));
    expect(other.offset, 0);
    verify?.call();
    await dragTableThumb(tester, table, axis, -forward);
    expect(controller.offset, closeTo(0, .5));
    verify?.call();
    final bounds = tester.getRect(table);
    await tester.tapAt(
        axis == Axis.horizontal
            ? Offset(bounds.right - 40, bounds.bottom - 12)
            : Offset(bounds.right - 12, bounds.bottom - 40),
        kind: PointerDeviceKind.mouse);
    await tester.pump(const Duration(milliseconds: 120));
    await tester.pumpAndSettle();
    expect(controller.offset, greaterThan(0));
    verify?.call();
    final cancelled = await tester.startGesture(
        tableThumb(tester, table, axis)!,
        kind: PointerDeviceKind.mouse);
    final beforeCancel = controller.offset;
    await cancelled.moveBy(
        axis == Axis.horizontal ? const Offset(-20, 0) : const Offset(0, -20));
    await tester.pump();
    expect(controller.offset, lessThan(beforeCancel));
    await cancelled.cancel();
    await tester.pumpAndSettle();
    final afterCancel = controller.offset;
    // Continue moving the same mouse device after cancelling its drag.
    await cancelled.moveTo(bounds.center);
    await cancelled.moveTo(bounds.topLeft);
    await tester.pump();
    expect(controller.offset, afterCancel,
        reason: 'A cancelled drag must not follow later mouse motion.');
    verify?.call();
    await dragTableThumb(tester, table, axis, -forward);
    expect(controller.offset, closeTo(0, .5));
    verify?.call();
  }
}
