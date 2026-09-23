import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jianpu_keyboard/features/converter/converter_panel_layout_persistence.dart';
import 'package:jianpu_keyboard/features/converter/resizable_panel.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('dragging a panel grip saves dimensions and double tap resets',
      (tester) async {
    var size = const ResizablePanelSize();

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: StatefulBuilder(
          builder: (context, setState) => SizedBox(
            width: 600,
            child: ResizablePanel(
              panelId: 'example',
              size: size,
              onSizeChanged: (next) => setState(() => size = next),
              child: const ColoredBox(color: Colors.white),
            ),
          ),
        ),
      ),
    ));

    final panel = find.byKey(const Key('resizable-panel-example'));
    final handle = find.byKey(const Key('example-resize-handle'));
    expect(tester.getSize(panel), const Size(600, 360));

    await tester.drag(handle, const Offset(-100, 50));
    await tester.pump();

    expect(size.width, 520);
    expect(size.height, 400);
    expect(tester.getSize(panel), const Size(520, 400));

    await tester.tap(handle);
    await tester.pump(const Duration(milliseconds: 80));
    await tester.tap(handle);
    await tester.pumpAndSettle();
    expect(size.isDefault, isTrue);
    expect(tester.getSize(panel), const Size(600, 360));
  });

  testWidgets('panel retains its saved width after a temporary width clamp',
      (tester) async {
    var availableWidth = 500.0;
    const saved = ResizablePanelSize(width: 640, height: 420);

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: StatefulBuilder(
          builder: (context, setState) => Column(children: [
            SizedBox(
              width: availableWidth,
              child: ResizablePanel(
                panelId: 'responsive',
                size: saved,
                onSizeChanged: (_) {},
                child: const ColoredBox(color: Colors.white),
              ),
            ),
            TextButton(
              onPressed: () => setState(() => availableWidth = 700),
              child: const Text('expand'),
            ),
          ]),
        ),
      ),
    ));

    final panel = find.byKey(const Key('resizable-panel-responsive'));
    expect(tester.getSize(panel), const Size(500, 420));

    await tester.tap(find.text('expand'));
    await tester.pump();
    expect(tester.getSize(panel), const Size(640, 420));
  });

  test('layout persistence stores valid non-default panel sizes', () async {
    final preferences = _PreferencesFake();
    final persistence = ConverterPanelLayoutPersistence(
      preferences: preferences,
    );

    await persistence.save({
      'smart-grid': const ResizablePanelSize(width: 720, height: 540),
      'text-preview': const ResizablePanelSize(),
    });
    final restored = await persistence.load();

    expect(restored.keys.toList(), ['smart-grid']);
    expect(restored['smart-grid']?.width, 720);
    expect(restored['smart-grid']?.height, 540);
  });

  test('layout persistence ignores malformed stored values', () async {
    final preferences = _PreferencesFake()
      ..values['jianpu_keyboard.converter_panel_layout.v1'] =
          '{"smart-grid":{"width":"wide"}}';
    final restored = await ConverterPanelLayoutPersistence(
      preferences: preferences,
    ).load();

    expect(restored, isEmpty);
  });
}

class _PreferencesFake extends Fake implements SharedPreferencesAsync {
  final Map<String, Object> values = {};

  @override
  Future<String?> getString(String key) async => values[key] as String?;

  @override
  Future<void> setString(String key, String value) async {
    values[key] = value;
  }
}
