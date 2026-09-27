import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jianpu_keyboard/features/converter/hover_table_scrollbars.dart';

void main() {
  testWidgets('reveals each overflowing scrollbar from its edge hot zone',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(home: _ScrollbarHarness()));
    await tester.pump();
    final origin =
        tester.getTopLeft(find.byKey(const Key('scrollbar-harness')));

    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: origin + const Offset(50, 50));
    await mouse.moveTo(origin + const Offset(195, 50));
    await tester.pump();
    expect(find.text('horizontal:false vertical:true'), findsOneWidget);

    await mouse.moveTo(origin + const Offset(50, 115));
    await tester.pump();
    expect(find.text('horizontal:true vertical:true'), findsOneWidget);
  });

  testWidgets('keeps a dragged scrollbar visible and hides it after the delay',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(home: _ScrollbarHarness()));
    await tester.pump();
    final origin =
        tester.getTopLeft(find.byKey(const Key('scrollbar-harness')));

    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: origin + const Offset(195, 50));
    await mouse.down(origin + const Offset(195, 50));
    await mouse.moveTo(origin + const Offset(50, 50));
    await tester.pump(const Duration(milliseconds: 120));
    expect(find.text('horizontal:false vertical:true'), findsOneWidget);

    await mouse.up();
    await tester.pump(const Duration(milliseconds: 99));
    expect(find.text('horizontal:false vertical:true'), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 1));
    expect(find.text('horizontal:false vertical:false'), findsOneWidget);
  });

  testWidgets('does not reveal scrollbars when content does not overflow',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(
        home: _ScrollbarHarness(
      overflow: false,
    )));
    await tester.pump();
    final origin =
        tester.getTopLeft(find.byKey(const Key('scrollbar-harness')));

    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: origin + const Offset(195, 115));
    await tester.pump();

    expect(find.text('horizontal:false vertical:false'), findsOneWidget);
  });

  testWidgets('keeps the horizontal scrollbar visible through a parent rebuild',
      (tester) async {
    await tester
        .pumpWidget(const MaterialApp(home: _FocusableScrollbarHarness()));
    await tester.pump();
    final harness = find.byKey(const Key('focusable-scrollbar-harness'));
    final origin = tester.getTopLeft(harness);
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);

    await mouse.addPointer(location: origin + const Offset(100, 115));
    await tester.pump();
    expect(
      find.textContaining('horizontal:true vertical:false'),
      findsOneWidget,
    );

    tester
        .state<_FocusableScrollbarHarnessState>(
          find.byType(_FocusableScrollbarHarness),
        )
        .rebuild();
    await tester.pump();
    expect(
      find.textContaining('horizontal:true vertical:false'),
      findsOneWidget,
    );
  });

  testWidgets(
      'reveals the horizontal scrollbar again after a focused cell rebuild',
      (tester) async {
    await tester
        .pumpWidget(const MaterialApp(home: _FocusableScrollbarHarness()));
    await tester.pump();
    final harness = find.byKey(const Key('focusable-scrollbar-harness'));
    final origin = tester.getTopLeft(harness);
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);

    await mouse.addPointer(location: origin + const Offset(100, 115));
    await tester.pump();
    expect(
      find.textContaining('horizontal:true vertical:false'),
      findsOneWidget,
    );

    await mouse.moveTo(origin + const Offset(100, 60));
    await tester.pump(const Duration(milliseconds: 100));
    expect(
      find.textContaining('horizontal:false vertical:false'),
      findsOneWidget,
    );

    final field = find.byKey(const Key('focusable-cell'));
    await mouse.moveTo(tester.getCenter(field));
    await tester.tap(field, kind: PointerDeviceKind.mouse);
    await tester.pump();
    expect(
        tester
            .widget<EditableText>(find.byType(EditableText))
            .focusNode
            .hasFocus,
        isTrue);

    await mouse.moveTo(origin + const Offset(100, 115));
    await tester.pump();
    expect(
      find.textContaining('horizontal:true vertical:false'),
      findsOneWidget,
    );
  });
}

class _ScrollbarHarness extends StatefulWidget {
  const _ScrollbarHarness({this.overflow = true});

  final bool overflow;

  @override
  State<_ScrollbarHarness> createState() => _ScrollbarHarnessState();
}

class _ScrollbarHarnessState extends State<_ScrollbarHarness> {
  final _horizontal = ScrollController();
  final _vertical = ScrollController();

  @override
  void dispose() {
    _horizontal.dispose();
    _vertical.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final width = widget.overflow ? 400.0 : 200.0;
    final height = widget.overflow ? 400.0 : 120.0;
    return Scaffold(
      body: Center(
        child: SizedBox(
          key: const Key('scrollbar-harness'),
          width: 200,
          height: 120,
          child: HoverTableScrollbars(
            horizontalController: _horizontal,
            verticalController: _vertical,
            hideDelay: const Duration(milliseconds: 100),
            builder: (context, showHorizontal, showVertical) => Stack(
              children: [
                Scrollbar(
                  controller: _horizontal,
                  thumbVisibility: showHorizontal,
                  notificationPredicate: (notification) =>
                      notification.metrics.axis == Axis.horizontal,
                  child: SingleChildScrollView(
                    controller: _horizontal,
                    scrollDirection: Axis.horizontal,
                    child: SizedBox(
                      width: width,
                      height: 120,
                      child: Scrollbar(
                        controller: _vertical,
                        thumbVisibility: showVertical,
                        child: ListView.builder(
                          controller: _vertical,
                          itemExtent: 40,
                          itemCount: (height / 40).round(),
                          itemBuilder: (context, index) => Text('$index'),
                        ),
                      ),
                    ),
                  ),
                ),
                Text('horizontal:$showHorizontal vertical:$showVertical'),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _FocusableScrollbarHarness extends StatefulWidget {
  const _FocusableScrollbarHarness();

  @override
  State<_FocusableScrollbarHarness> createState() =>
      _FocusableScrollbarHarnessState();
}

class _FocusableScrollbarHarnessState
    extends State<_FocusableScrollbarHarness> {
  final _horizontal = ScrollController();
  final _vertical = ScrollController();
  var _rebuildCount = 0;

  void rebuild() => setState(() => _rebuildCount++);

  @override
  void dispose() {
    _horizontal.dispose();
    _vertical.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: SizedBox(
          key: const Key('focusable-scrollbar-harness'),
          width: 200,
          height: 120,
          child: HoverTableScrollbars(
            horizontalController: _horizontal,
            verticalController: _vertical,
            hideDelay: const Duration(milliseconds: 100),
            builder: (context, showHorizontal, showVertical) => Stack(
              children: [
                Scrollbar(
                  controller: _horizontal,
                  thumbVisibility: showHorizontal,
                  notificationPredicate: (notification) =>
                      notification.metrics.axis == Axis.horizontal,
                  child: SingleChildScrollView(
                    controller: _horizontal,
                    scrollDirection: Axis.horizontal,
                    child: const SizedBox(width: 400, height: 120),
                  ),
                ),
                Positioned(
                  left: 20,
                  top: 30,
                  width: 100,
                  height: 48,
                  child: TextField(
                    key: const Key('focusable-cell'),
                    onTap: rebuild,
                  ),
                ),
                Positioned(
                  left: 125,
                  top: 30,
                  child: Text(
                    'horizontal:$showHorizontal vertical:$showVertical '
                    'rebuild:$_rebuildCount',
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
