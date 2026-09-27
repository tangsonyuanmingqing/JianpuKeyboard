import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jianpu_keyboard/features/converter/smart_grid_issue_overlay.dart';
import 'package:jianpu_keyboard/features/converter/smart_grid_validation.dart';
import 'package:jianpu_keyboard/features/converter/table_scale.dart';

void main() {
  testWidgets('row glyph pixels match the previous Icon cell decoration',
      (tester) async {
    await tester.runAsync(() async {
      await (FontLoader('MaterialIcons')
            ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf')))
          .load();
    });
    final boundary = GlobalKey();
    for (final percent in [0, 50, 100]) {
      final scale = TableScale(percent);
      final cellSize = scale.dimension(58);
      const errorColor = Colors.red;
      final warningColor = Colors.amber.shade800;
      final theme = ThemeData(
          colorScheme:
              ColorScheme.fromSeed(seedColor: Colors.blue, error: errorColor));
      for (final direction in TextDirection.values) {
        Future<List<int>> capture(Widget child) async {
          await tester.pumpWidget(MaterialApp(
            theme: theme,
            home: Directionality(
              textDirection: direction,
              child: Center(
                child: RepaintBoundary(
                  key: boundary,
                  child: SizedBox(
                    width: cellSize * 2,
                    height: cellSize,
                    child: child,
                  ),
                ),
              ),
            ),
          ));
          await tester.pump();
          return (await tester.runAsync(() async {
            final image = await (boundary.currentContext!.findRenderObject()!
                    as RenderRepaintBoundary)
                .toImage(pixelRatio: 1.5);
            try {
              final data =
                  await image.toByteData(format: ui.ImageByteFormat.rawRgba);
              return data!.buffer.asUint8List().toList();
            } finally {
              image.dispose();
            }
          }))!;
        }

        Widget cells({required bool legacyIcons}) => Row(
              textDirection: TextDirection.ltr,
              children: [
                for (final (icon, color) in [
                  (Icons.error, errorColor),
                  (Icons.warning_amber_rounded, warningColor),
                ])
                  Container(
                    width: cellSize,
                    height: cellSize,
                    decoration: BoxDecoration(
                        border: Border.all(color: color, width: 2)),
                    padding: EdgeInsets.all(scale.dimension(3)),
                    child: Stack(children: [
                      const Positioned.fill(child: SizedBox.expand()),
                      if (legacyIcons)
                        Positioned(
                            right: 0,
                            top: 0,
                            child: IgnorePointer(
                                child: Icon(icon, size: 13, color: color))),
                    ]),
                  ),
              ],
            );
        final original = await capture(cells(legacyIcons: true));
        final optimized = await capture(SmartGridIssueOverlay(
          leadingWidth: 0,
          scale: scale,
          issues: const [
            SmartGridIssue(
                row: 0,
                column: 0,
                severity: SmartGridIssueSeverity.error,
                message: 'error'),
            SmartGridIssue(
                row: 0,
                column: 1,
                severity: SmartGridIssueSeverity.warning,
                message: 'warning'),
          ],
          child: cells(legacyIcons: false),
        ));
        expect(optimized, original,
            reason: 'scale=$percent, direction=$direction');
      }
    }
  });
}
