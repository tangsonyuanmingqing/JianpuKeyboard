import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' show FramePhase, FrameTiming;

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show debugProfileLayoutsEnabled;
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:jianpu_keyboard/app/app.dart';
import 'package:jianpu_keyboard/features/converter/converter_draft_persistence.dart';
import 'package:jianpu_keyboard/features/converter/converter_panel_layout_persistence.dart';
import 'package:jianpu_keyboard/features/converter/converter_providers.dart';
import 'package:jianpu_keyboard/features/converter/smart_grid_codec.dart';
import 'package:jianpu_keyboard/features/converter/smart_grid_document.dart';
import 'package:jianpu_keyboard/features/converter/smart_grid_editor.dart';
import 'package:jianpu_keyboard/features/converter/smart_grid_text_field.dart';
import 'package:jianpu_keyboard/features/converter/smart_grid_issue_overlay.dart';
import 'package:jianpu_keyboard/features/converter/resizable_panel.dart';
import 'package:jianpu_keyboard/features/converter/table_scale.dart';
import 'package:jianpu_keyboard/features/library/song_library_persistence.dart';
import 'package:jianpu_keyboard/features/library/song_library_providers.dart';
import 'package:jianpu_keyboard/infrastructure/app_data_store.dart';
import 'package:jianpu_keyboard/infrastructure/recovery_providers.dart';
import 'package:jianpu_keyboard/infrastructure/recovery_snapshot_repository.dart';
import 'package:jianpu_keyboard/infrastructure/storage_health.dart';

const _validationOnly = bool.fromEnvironment('UI_PERFORMANCE_VALIDATE_ONLY');
const _traceSelection = bool.fromEnvironment('UI_PERFORMANCE_TRACE_SELECTION');
const _warmupCount = _validationOnly ? 2 : 10;
const _sampleCount = _validationOnly ? 2 : 50;
const _budgetMs = 100;
const _scenario = String.fromEnvironment('UI_PERFORMANCE_SCENARIO',
    defaultValue: 'default-valid');
const _denseErrors =
    _scenario == 'default-errors' || _scenario == 'large-errors';
const _largePanel = _scenario == 'large-valid' || _scenario == 'large-errors';
const _expectedErrors = _denseErrors ? 9999 : 0;

// Only visual preferences are injected. All content persistence remains real.
class _FixturePanelLayout extends ConverterPanelLayoutPersistence {
  @override
  Future<Map<String, ResizablePanelSize>> load() async => _largePanel
      ? const {'smart-grid': ResizablePanelSize(width: 1230, height: 1200)}
      : const {};

  @override
  Future<void> save(Map<String, ResizablePanelSize> sizes) async {
    throw StateError(
        'The benchmark must not resize or save panel preferences.');
  }
}

class _Sample {
  const _Sample(this.startedAtUs, this.frameNumber);

  final int startedAtUs;
  final int frameNumber;
}

SmartGridDocument _populatedDocument() {
  final seed = SmartGridDocument.empty(rows: 100, columns: 100);
  return SmartGridDocument(
    columnCount: 100,
    selectedRow: 0,
    selectedColumn: 1,
    rows: [
      for (var row = 0; row < seed.rows.length; row++)
        seed.rows[row].copyWith(cells: [
          for (var column = 0; column < 100; column++)
            if (row == 0 && column == 1)
              '4'
            else if (_denseErrors)
              row.isEven ? '8' : ';'
            else
              row.isEven ? '${(row + column) % 7 + 1}' : '晨光照大地'[column % 5],
        ]),
    ],
  );
}

Map<String, Object> _distribution(List<double> values) {
  final sorted = [...values]..sort();
  double percentile(double fraction) =>
      sorted[(math.max(1, (sorted.length * fraction).ceil())) - 1];
  return {
    'sample_count': sorted.length,
    'p50_ms': percentile(.50),
    'p95_ms': percentile(.95),
    'max_ms': sorted.last,
    'samples_ms': values,
  };
}

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('100x100 Windows UI response performance', (tester) async {
    expect(Platform.isWindows, isTrue, reason: 'Run on the Windows device.');
    expect(kProfileMode, isTrue, reason: 'Run flutter drive with --profile.');
    expect(['default-valid', 'default-errors', 'large-valid', 'large-errors'],
        contains(_scenario));
    expect(!_traceSelection || _validationOnly, isTrue,
        reason: 'Enhanced tracing is diagnostic only, not acceptance data.');

    // Keep real repository writes while isolating all score/draft/snapshot data.
    final dataRoot = await Directory.systemTemp.createTemp('jianpu-ui-perf-');
    final store = AtomicFileStore(
      directoryProvider: FixedAppDataDirectoryProvider(dataRoot),
    );
    final document = _populatedDocument();
    final container = ProviderContainer(overrides: [
      initialSmartGridDocumentProvider.overrideWithValue(document),
      initialConverterInputProvider.overrideWithValue(
        const SmartGridCodec().exportInput(document),
      ),
      initialEditorModeProvider.overrideWithValue(ConverterEditorMode.grid),
      initialTableScaleProvider.overrideWithValue(const TableScale()),
      converterPanelLayoutPersistenceProvider
          .overrideWithValue(_FixturePanelLayout()),
      converterDraftPersistenceProvider.overrideWithValue(
        ConverterDraftPersistence(store: store),
      ),
      songLibraryPersistenceProvider.overrideWithValue(
        SongLibraryPersistence(store: store),
      ),
      recoverySnapshotRepositoryProvider.overrideWithValue(
        RecoverySnapshotRepository(store: store),
      ),
    ]);
    final frames = <int, FrameTiming>{};
    void collectFrames(List<FrameTiming> timings) {
      for (final timing in timings) {
        frames[timing.frameNumber] = timing;
      }
    }

    final originalPolicy = binding.framePolicy;
    binding.addTimingsCallback(collectFrames);
    binding.reportData = {
      'recorded_at': DateTime.now().toUtc().toIso8601String(),
      'platform': Platform.operatingSystem,
      'os_version': Platform.operatingSystemVersion,
      'dart_version': Platform.version,
      'build_mode': 'profile',
      'validation_only': _validationOnly,
      'enhanced_tracing': _traceSelection,
      'grid_rows': 100,
      'grid_columns': 100,
      'fixture': 'fully populated alternating score/lyrics rows',
      'scenario': _scenario,
      'expected_error_count': _expectedErrors,
      'warmup_per_operation': _warmupCount,
      'samples_per_operation': _sampleCount,
      'budget_ms': _budgetMs,
      'data_directory': dataRoot.path,
      'measurement': 'synthetic framework input dispatch to matching frame '
          'rasterFinishWallTime; excludes OS input and display scanout',
      'operations': <String, Object>{},
    };

    try {
      await tester.pumpWidget(UncontrolledProviderScope(
        container: container,
        child: const JianpuKeyboardApp(),
      ));
      await tester.pumpAndSettle();
      final firstCell = find.byKey(const ValueKey('grid-cell-row-1:1'));
      final secondCell = find.byKey(const ValueKey('grid-cell-row-1:2'));
      // The default ensureVisible alignment can put the cell underneath the
      // frozen header pane. Keep an already visible cell in its current place.
      await Scrollable.ensureVisible(
        tester.element(firstCell),
        alignmentPolicy: ScrollPositionAlignmentPolicy.keepVisibleAtEnd,
      );
      await tester.pumpAndSettle();
      expect(firstCell.hitTestable(), findsOneWidget);
      expect(secondCell.hitTestable(), findsOneWidget);
      final firstPosition = tester.getCenter(firstCell);
      final secondPosition = tester.getCenter(secondCell);
      final editor =
          tester.widget<SmartGridEditor>(find.byType(SmartGridEditor));
      final panelSize = tester.getSize(
        find.byKey(const Key('resizable-panel-smart-grid')),
      );
      expect(editor.issues, hasLength(_expectedErrors));
      expect(editor.scale.percent, TableScale.defaultPercent);
      expect(
          panelSize.height, _largePanel ? 1200 : ResizablePanel.defaultHeight);
      if (_largePanel) expect(panelSize.width, 1230);
      final secondMarker = tester
          .widget<SmartGridIssueOverlay>(
              find.byKey(const ValueKey('grid-issues-row-1')))
          .issues
          .where((issue) => issue.column == 2);
      expect(secondMarker, _denseErrors ? hasLength(1) : isEmpty);
      binding.reportData!.addAll({
        'physical_width': tester.view.physicalSize.width,
        'physical_height': tester.view.physicalSize.height,
        'device_pixel_ratio': tester.view.devicePixelRatio,
        'table_scale_percent': editor.scale.percent,
        'panel_width': panelSize.width,
        'panel_height': panelSize.height,
        'observed_error_count': editor.issues.length,
      });

      // Remove artificial pumped frames; native vsync drives each changed frame.
      binding.framePolicy =
          LiveTestWidgetsFlutterBindingFramePolicy.benchmarkLive;
      tester.testTextInput.register();
      await tester.tapAt(firstPosition);
      await binding.endOfFrame;
      await tester.showKeyboard(firstCell);
      await binding.endOfFrame;
      expect(
        tester
            .widget<EditableText>(find.descendant(
              of: firstCell,
              matching: find.byType(EditableText),
            ))
            .focusNode
            .hasFocus,
        isTrue,
      );

      Future<_Sample> measure(Future<void> Function() action) async {
        final startedAtUs = DateTime.now().microsecondsSinceEpoch;
        await action();
        final rendered = Completer<int>();
        binding.addPostFrameCallback((_) {
          rendered.complete(binding.platformDispatcher.frameData.frameNumber);
        });
        await binding.endOfFrame;
        return _Sample(startedAtUs, await rendered.future);
      }

      Future<void> benchmark(
        String name,
        Future<void> Function(int index) action, {
        Future<void> Function(int index)? prepare,
        required void Function(int index) verify,
      }) async {
        final samples = <_Sample>[];
        for (var index = 0; index < _warmupCount + _sampleCount; index++) {
          if (prepare != null) await prepare(index);
          late final _Sample sample;
          if (_traceSelection && name == 'selection' && index == _warmupCount) {
            final oldBuilds = debugProfileBuildsEnabled;
            final oldLayouts = debugProfileLayoutsEnabled;
            try {
              debugProfileBuildsEnabled = true;
              debugProfileLayoutsEnabled = true;
              await binding.traceAction(() async {
                sample = await measure(() => action(index));
              }, reportKey: 'selection_timeline');
            } finally {
              debugProfileBuildsEnabled = oldBuilds;
              debugProfileLayoutsEnabled = oldLayouts;
            }
          } else {
            sample = await measure(() => action(index));
          }
          verify(index);
          expect(tester.takeException(), isNull);
          if (index >= _warmupCount) samples.add(sample);
          if (index == _warmupCount - 1) {
            debugPrint('UI_PERF $name: warmup complete');
          }
        }
        // Engine timing callbacks arrive in batches. Their delivery delay is
        // excluded: each sample uses its matched frame's own finish timestamp.
        final deadline = DateTime.now().add(const Duration(seconds: 10));
        while (
            samples.any((sample) => !frames.containsKey(sample.frameNumber))) {
          if (DateTime.now().isAfter(deadline)) {
            fail(
                'Missing raster timing for $name; no substitute measurements.');
          }
          await Future<void>.delayed(const Duration(milliseconds: 100));
        }
        final latency = <double>[];
        final build = <double>[];
        final raster = <double>[];
        final raw = <Map<String, Object>>[];
        for (final sample in samples) {
          final frame = frames[sample.frameNumber]!;
          final finishUs = frame.timestampInMicroseconds(
            FramePhase.rasterFinishWallTime,
          );
          final latencyMs = (finishUs - sample.startedAtUs) / 1000;
          expect(latencyMs, greaterThanOrEqualTo(0));
          latency.add(latencyMs);
          build.add(frame.buildDuration.inMicroseconds / 1000);
          raster.add(frame.rasterDuration.inMicroseconds / 1000);
          raw.add({
            'frame_number': sample.frameNumber,
            'input_dispatch_wall_us': sample.startedAtUs,
            'raster_finish_wall_us': finishUs,
          });
        }
        final summary = _distribution(latency);
        final operations =
            binding.reportData!['operations'] as Map<String, Object>;
        operations[name] = {
          'response': summary,
          'build': _distribution(build),
          'raster': _distribution(raster),
          'passed': (summary['p95_ms']! as double) < _budgetMs,
          'raw_frames': raw,
        };
        debugPrint('UI_PERF $name: p95=${summary['p95_ms']}ms, '
            'max=${summary['max_ms']}ms');
      }

      await benchmark('input', (index) async {
        await tester.enterText(firstCell, index.isEven ? '3' : '4');
      }, verify: (index) {
        expect(container.read(smartGridDocumentProvider).rows[0].cells[1],
            index.isEven ? '3' : '4',
            reason: 'input iteration $index');
        expect(tester.widget<SmartGridTextField>(firstCell).controller.text,
            index.isEven ? '3' : '4');
      });

      await benchmark('selection', (index) async {
        await tester.tapAt(index.isEven ? secondPosition : firstPosition);
      }, verify: (index) {
        final selected = container.read(smartGridDocumentProvider);
        expect(selected.selectedRow, 0);
        expect(selected.selectedColumn, index.isEven ? 2 : 1);
      });

      final verticalLists = tester
          .widgetList<ReorderableListView>(
            find.descendant(
              of: find.byType(SmartGridEditor),
              matching: find.byType(ReorderableListView),
            ),
          )
          .toList();
      expect(verticalLists, hasLength(2));
      final body = verticalLists.first.scrollController!;
      final frozen = verticalLists.last.scrollController!;
      final horizontal = tester
          .widget<SingleChildScrollView>(
            find
                .descendant(
                  of: find.byType(SmartGridEditor),
                  matching: find.byType(SingleChildScrollView),
                )
                .first,
          )
          .controller!;
      final scrollPosition = firstPosition + const Offset(140, 20);
      var verticalDirection = 1;
      var expectedVertical = body.offset;
      var greatestVertical = body.offset;

      await benchmark('vertical_scroll', (index) async {
        if (body.offset >= body.position.maxScrollExtent - .5) {
          verticalDirection = -1;
        } else if (body.offset <= .5) {
          verticalDirection = 1;
        }
        final step = _validationOnly ? body.position.maxScrollExtent / 2 : 180;
        expectedVertical = (body.offset + verticalDirection * step)
            .clamp(0.0, body.position.maxScrollExtent);
        final delta = expectedVertical - body.offset;
        expect(delta.abs(), greaterThan(0));
        await tester.sendEventToBinding(PointerScrollEvent(
          kind: PointerDeviceKind.mouse,
          position: scrollPosition,
          scrollDelta: Offset(0, delta),
        ));
      }, verify: (index) {
        expect(body.offset, closeTo(expectedVertical, .5));
        expect(frozen.offset, closeTo(body.offset, .5));
        greatestVertical = math.max(greatestVertical, body.offset);
      });
      expect(greatestVertical, closeTo(body.position.maxScrollExtent, .5));
      body.jumpTo(0);
      await binding.endOfFrame;

      var horizontalDirection = 1;
      var expectedHorizontal = horizontal.offset;
      var greatestHorizontal = horizontal.offset;

      await benchmark('horizontal_scroll', (index) async {
        if (horizontal.offset >= horizontal.position.maxScrollExtent - .5) {
          horizontalDirection = -1;
        } else if (horizontal.offset <= .5) {
          horizontalDirection = 1;
        }
        final step =
            _validationOnly ? horizontal.position.maxScrollExtent / 2 : 180;
        expectedHorizontal = (horizontal.offset + horizontalDirection * step)
            .clamp(0.0, horizontal.position.maxScrollExtent);
        final delta = expectedHorizontal - horizontal.offset;
        expect(delta.abs(), greaterThan(0));
        await tester.sendEventToBinding(PointerScrollEvent(
          kind: PointerDeviceKind.mouse,
          position: scrollPosition,
          scrollDelta: Offset(delta, 0),
        ));
      }, verify: (index) {
        expect(horizontal.offset, closeTo(expectedHorizontal, .5));
        greatestHorizontal = math.max(greatestHorizontal, horizontal.offset);
      });
      expect(
          greatestHorizontal, closeTo(horizontal.position.maxScrollExtent, .5));
      binding.reportData!['scroll_coverage'] = {
        'vertical_max_reached': greatestVertical,
        'vertical_extent': body.position.maxScrollExtent,
        'horizontal_max_reached': greatestHorizontal,
        'horizontal_extent': horizontal.position.maxScrollExtent,
      };
      horizontal.jumpTo(0);
      await binding.endOfFrame;

      await tester.tapAt(firstPosition);
      await binding.endOfFrame;
      await tester.showKeyboard(firstCell);
      await binding.endOfFrame;
      await benchmark('undo', (index) async {
        // Debug key names are absent in Profile; explicit physical keys avoid
        // the test simulator's debug-name-based fallback lookup.
        await tester.sendKeyDownEvent(
          LogicalKeyboardKey.controlLeft,
          physicalKey: PhysicalKeyboardKey.controlLeft,
        );
        try {
          await tester.sendKeyEvent(
            LogicalKeyboardKey.keyZ,
            physicalKey: PhysicalKeyboardKey.keyZ,
          );
        } finally {
          await tester.sendKeyUpEvent(
            LogicalKeyboardKey.controlLeft,
            physicalKey: PhysicalKeyboardKey.controlLeft,
          );
        }
      }, prepare: (index) async {
        await tester.enterText(firstCell, '5');
        await binding.endOfFrame;
        expect(container.read(smartGridDocumentProvider).rows[0].cells[1], '5');
      }, verify: (index) {
        expect(container.read(smartGridDocumentProvider).rows[0].cells[1], '4');
        expect(
            tester.widget<SmartGridTextField>(firstCell).controller.text, '4');
      });

      await container.read(converterInputProvider.notifier).flush();
      expect(container.read(draftWriteStateProvider).phase,
          PersistenceWritePhase.saved);
      expect(
          tester.widget<SmartGridEditor>(find.byType(SmartGridEditor)).issues,
          hasLength(_expectedErrors));
      final operations =
          binding.reportData!['operations'] as Map<String, Object>;
      final failures = operations.entries
          .where(
              (entry) => (entry.value as Map<String, Object>)['passed'] != true)
          .map((entry) => entry.key)
          .toList();
      binding.reportData!['passed'] = failures.isEmpty;
      if (!_validationOnly) {
        expect(failures, isEmpty, reason: 'P95 >= ${_budgetMs}ms: $failures');
      }
    } finally {
      binding.framePolicy = originalPolicy;
      binding.removeTimingsCallback(collectFrames);
      tester.testTextInput.unregister();
      try {
        await tester.pumpWidget(const SizedBox.shrink());
      } finally {
        container.dispose();
      }
    }
  }, timeout: const Timeout(Duration(minutes: 8)));
}
