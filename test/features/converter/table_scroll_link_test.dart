import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jianpu_keyboard/features/converter/table_scroll_link.dart';

void main() {
  testWidgets(
      'links unequal extents and unregisters without owning controllers',
      (tester) async {
    final first = ScrollController();
    final second = ScrollController();
    final link = TableScrollLink(first, second);
    // No clients yet: listening must not assume an attached ScrollPosition.
    await tester.pumpWidget(MaterialApp(
      home: Row(children: [
        for (final (controller, height) in [(first, 2000.0), (second, 1000.0)])
          Expanded(
            child: SizedBox(
              height: 200,
              child: SingleChildScrollView(
                controller: controller,
                child: SizedBox(height: height),
              ),
            ),
          ),
      ]),
    ));
    first.jumpTo(120);
    expect(second.offset, 120);
    second.jumpTo(220);
    expect(first.offset, 220);
    first.jumpTo(1500);
    expect(second.offset, second.position.maxScrollExtent);
    // Clamping must not bounce the source back or start a listener loop.
    expect(first.offset, 1500);
    link.dispose();
    first.jumpTo(100);
    expect(second.offset, second.position.maxScrollExtent);
    await tester.pumpWidget(const SizedBox.shrink());
    first.dispose();
    second.dispose();
    expect(tester.takeException(), isNull);
  });
}
