import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jianpu_keyboard/app/theme/app_theme.dart';
import 'package:jianpu_keyboard/app/theme/app_typography.dart';
import 'package:jianpu_keyboard/features/converter/converter_draft_persistence.dart';
import 'package:jianpu_keyboard/features/converter/converter_page.dart';
import 'package:jianpu_keyboard/features/converter/converter_providers.dart';
import 'package:jianpu_keyboard/features/library/song_library_persistence.dart';
import 'package:jianpu_keyboard/features/library/song_library_providers.dart';
import 'package:jianpu_keyboard/infrastructure/recovery_providers.dart';
import 'package:jianpu_keyboard/infrastructure/recovery_snapshot_repository.dart';
import 'package:jianpu_keyboard/infrastructure/storage_health.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  RecoverySnapshotRepository testSnapshots() {
    return _RecoverySnapshotsFake();
  }

  Future<void> pumpPage(
    WidgetTester tester, {
    ProviderContainer? container,
  }) async {
    tester.view.physicalSize = const Size(1200, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final Widget app = container == null
        ? ProviderScope(
            child: MaterialApp(
              theme: AppTheme.light(),
              home: const ConverterPage(),
            ),
          )
        : UncontrolledProviderScope(
            container: container,
            child: MaterialApp(
                theme: AppTheme.light(), home: const ConverterPage()),
          );
    await tester.pumpWidget(app);
  }

  testWidgets('does not convert score input automatically', (tester) async {
    await pumpPage(tester);

    await tester.enterText(find.byKey(const Key('score-input')), '3 4 5');
    await tester.pump();

    expect(find.text('Ｄ Ｆ Ｇ'), findsNothing);
    expect(find.text('转换结果将显示在这里'), findsOneWidget);
  });

  testWidgets('uses the notation font for text input and pure text output',
      (tester) async {
    await pumpPage(tester);

    final scoreInput = find.byKey(const Key('score-input'));
    final scoreEditor = tester.widget<EditableText>(
      find.descendant(of: scoreInput, matching: find.byType(EditableText)),
    );
    final output = tester.widget<SelectableText>(
      find.byKey(const Key('output-text')),
    );

    expect(scoreEditor.style.fontFamily, AppTypography.notationFamily);
    expect(output.style?.fontFamily, AppTypography.notationFamily);
  });

  testWidgets('adds a semicolon when Enter is pressed before later score text',
      (tester) async {
    await pumpPage(tester);
    final scoreInput = find.byKey(const Key('score-input'));
    await tester.enterText(scoreInput, '3 4 5\n[词] 我爱');
    await tester.tap(scoreInput);
    tester
        .widget<EditableText>(
          find.descendant(of: scoreInput, matching: find.byType(EditableText)),
        )
        .controller
        .selection = const TextSelection.collapsed(offset: 5);
    tester.testTextInput.updateEditingValue(
      const TextEditingValue(
        text: '3 4 5\n\n[词] 我爱',
        selection: TextSelection.collapsed(offset: 6),
      ),
    );
    await tester.pump();

    expect(
      tester
          .widget<EditableText>(
            find.descendant(
                of: scoreInput, matching: find.byType(EditableText)),
          )
          .controller
          .text,
      '3 4 5;\n\n[词] 我爱',
    );
  });

  testWidgets('converts only after the convert button is pressed',
      (tester) async {
    await pumpPage(tester);

    await tester.enterText(find.byKey(const Key('score-input')), '3 4 5');
    await tester.pump();
    await tester.tap(find.byKey(const Key('convert-button')));
    await tester.pump();

    expect(find.text('Ｄ Ｆ Ｇ'), findsOneWidget);
  });

  testWidgets('clears the previous result when input changes', (tester) async {
    await pumpPage(tester);

    await tester.enterText(find.byKey(const Key('score-input')), '3 4 5');
    await tester.pump();
    await tester.tap(find.byKey(const Key('convert-button')));
    await tester.pump();
    expect(find.text('Ｄ Ｆ Ｇ'), findsOneWidget);

    await tester.enterText(find.byKey(const Key('score-input')), '3 4 5 6');
    await tester.pump();

    expect(find.text('Ｄ Ｆ Ｇ'), findsNothing);
    expect(find.text('Ｄ Ｆ Ｇ Ｈ'), findsNothing);
    expect(find.text('转换结果将显示在这里'), findsOneWidget);
  });

  testWidgets('does not convert lyrics until convert is pressed',
      (tester) async {
    await pumpPage(tester);

    await tester.enterText(find.byKey(const Key('score-input')), '3 4 5');
    await tester.enterText(find.byKey(const Key('lyrics-input')), '我爱你');
    await tester.pump();

    expect(
      tester.widget<SelectableText>(find.byKey(const Key('output-text'))).data,
      '转换结果将显示在这里',
    );

    await tester.tap(find.byKey(const Key('convert-button')));
    await tester.pump();

    expect(
      tester.widget<SelectableText>(find.byKey(const Key('output-text'))).data,
      'Ｄ Ｆ Ｇ\n我 爱 你',
    );
  });

  testWidgets('copies converted output', (tester) async {
    String? clipboardText;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          clipboardText = (call.arguments as Map)['text'] as String?;
          return null;
        }
        if (call.method == 'Clipboard.getData') {
          return <String, dynamic>{'text': clipboardText};
        }
        return null;
      },
    );

    await pumpPage(tester);

    await tester.enterText(find.byKey(const Key('score-input')), '3 4 5');
    await tester.pump();
    await tester.tap(find.byKey(const Key('convert-button')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('copy-button')));
    await tester.pump();

    expect(clipboardText, 'Ｄ Ｆ Ｇ');
  });

  testWidgets(
      'shows a pending-save state and includes the song title when copying',
      (tester) async {
    String? clipboardText;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          clipboardText = (call.arguments as Map)['text'] as String?;
        }
        return null;
      },
    );

    await pumpPage(tester);
    await tester.enterText(find.byKey(const Key('song-title-input')), '晨光');
    await tester.pump();

    expect(find.text('待保存到曲谱库'), findsOneWidget);

    await tester.enterText(find.byKey(const Key('score-input')), '3 4 5');
    await tester.tap(find.byKey(const Key('convert-button')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('copy-button')));
    await tester.pump();

    expect(clipboardText, '晨光\n\nＤ Ｆ Ｇ');
  });

  testWidgets('saves the homepage song title without asking for it again',
      (tester) async {
    final preferences = _PreferencesFake();
    final container = ProviderContainer(overrides: [
      converterDraftPersistenceProvider.overrideWithValue(
        ConverterDraftPersistence(preferences: preferences),
      ),
      songLibraryPersistenceProvider.overrideWithValue(
        SongLibraryPersistence(preferences: preferences),
      ),
      recoverySnapshotRepositoryProvider.overrideWithValue(testSnapshots()),
    ]);
    addTearDown(container.dispose);
    await pumpPage(tester, container: container);

    await tester.enterText(find.byKey(const Key('song-title-input')), '晨光');
    await tester.enterText(find.byKey(const Key('score-input')), '3 4 5');
    await tester.tap(find.byKey(const Key('save-song-button')));
    await tester.pumpAndSettle();

    expect(find.text('保存到曲谱库'), findsNWidgets(2));
    expect(find.byType(AlertDialog), findsOneWidget);
    expect(find.widgetWithText(TextField, '歌曲名 *'), findsNothing);

    await tester.tap(find.byKey(const Key('song-dialog-save')));
    await tester.pumpAndSettle();

    expect(
      container.read(songLibraryWriteStateProvider).phase,
      PersistenceWritePhase.saved,
      reason: container.read(songLibraryWriteStateProvider).message,
    );
    expect(container.read(songLibraryProvider).single.title, '晨光');
  });

  testWidgets('accepts an empty homepage title from the save dialog',
      (tester) async {
    final preferences = _PreferencesFake();
    final container = ProviderContainer(overrides: [
      converterDraftPersistenceProvider.overrideWithValue(
        ConverterDraftPersistence(preferences: preferences),
      ),
      songLibraryPersistenceProvider.overrideWithValue(
        SongLibraryPersistence(preferences: preferences),
      ),
      recoverySnapshotRepositoryProvider.overrideWithValue(testSnapshots()),
    ]);
    addTearDown(container.dispose);
    await pumpPage(tester, container: container);

    await tester.enterText(find.byKey(const Key('score-input')), '3 4 5');
    await tester.tap(find.byKey(const Key('save-song-button')));
    await tester.pumpAndSettle();

    final titleField = find.widgetWithText(TextField, '歌曲名 *');
    expect(titleField, findsOneWidget);
    await tester.enterText(titleField, '晚风');
    await tester.tap(find.byKey(const Key('song-dialog-save')));
    await tester.pumpAndSettle();

    expect(container.read(songLibraryProvider).single.title, '晚风');
    expect(
      tester
          .widget<TextField>(find.byKey(const Key('song-title-input')))
          .controller!
          .text,
      '晚风',
    );
  });

  testWidgets('keeps long structured score rows on one visual text line',
      (tester) async {
    final container = ProviderContainer();
    await pumpPage(tester, container: container);

    await tester.enterText(
      find.byKey(const Key('score-input')),
      '''[谱] 3 3 4 5 | 5 4 3 - // 2 2 3 4 | 3 2 1 -;
[词] 晨 光 落 在 | 窗 前 - // 轻 声 唱 起 | 新 的 歌 -;''',
    );
    await tester.tap(find.byKey(const Key('convert-button')));
    await tester.pump();

    final displayed = tester
        .widget<SelectableText>(find.byKey(const Key('output-text')))
        .data!;
    final converted = container.read(conversionResultProvider)!.output;
    expect(converted.split('\n'), hasLength(2));
    expect(displayed, converted);
    expect(
      find.ancestor(
        of: find.byKey(const Key('output-text')),
        matching: find.byWidgetPredicate(
          (widget) =>
              widget is SingleChildScrollView &&
              widget.scrollDirection == Axis.horizontal,
        ),
      ),
      findsOneWidget,
    );
    await tester.pumpWidget(const SizedBox.shrink());
    container.dispose();
  });

  testWidgets('aligns lyric continuation under the continued note',
      (tester) async {
    await pumpPage(tester);

    await tester.enterText(find.byKey(const Key('score-input')), '3 2 2 -');
    await tester.enterText(find.byKey(const Key('lyrics-input')), '低 垂 -');
    await tester.tap(find.byKey(const Key('convert-button')));
    await tester.pump();

    expect(
      tester.widget<SelectableText>(find.byKey(const Key('output-text'))).data,
      'Ｄ Ｓ Ｓ -\n低 垂 -',
    );
    expect(find.byKey(const Key('warning-text')), findsNothing);
  });

  testWidgets('copies aligned output without warnings', (tester) async {
    String? clipboardText;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          clipboardText = (call.arguments as Map)['text'] as String?;
        }
        return null;
      },
    );

    await pumpPage(tester);
    await tester.enterText(find.byKey(const Key('score-input')), '3 4');
    await tester.enterText(find.byKey(const Key('lyrics-input')), '我 爱 你');
    await tester.tap(find.byKey(const Key('convert-button')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('copy-button')));
    await tester.pump();

    expect(clipboardText, 'Ｄ Ｆ\n我 爱');
    expect(find.byKey(const Key('warning-text')), findsOneWidget);
    expect(clipboardText!.contains('歌词数量多于'), isFalse);
    expect(find.text('未匹配歌词：你（第 1 行第 3 项）'), findsOneWidget);
  });

  testWidgets('shows a message when copying without a result', (tester) async {
    await pumpPage(tester);

    await tester.tap(find.byKey(const Key('copy-button')));
    await tester.pump();

    expect(find.text('没有可复制的内容'), findsOneWidget);
  });

  testWidgets('clears input, output, warnings and unmatched lyrics',
      (tester) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    await pumpPage(tester, container: container);

    await tester.enterText(find.byKey(const Key('score-input')), '3 4');
    await tester.enterText(find.byKey(const Key('lyrics-input')), '我 爱 你');
    await tester.pump();
    await tester.tap(find.byKey(const Key('convert-button')));
    await tester.pump();

    expect(find.text('Ｄ Ｆ\n我 爱'), findsOneWidget);
    expect(find.byKey(const Key('warning-text')), findsOneWidget);
    expect(find.byKey(const Key('unmatched-lyrics-text')), findsOneWidget);

    await tester.tap(find.byKey(const Key('clear-button')));
    await tester.pump();
    expect(find.text('清空输入？'), findsOneWidget);
    await tester.tap(find.text('清空').last);
    await tester.pump();

    expect(find.byKey(const Key('score-input')), findsOneWidget);
    expect(
        tester
            .widget<TextField>(find.byKey(const Key('score-input')))
            .controller!
            .text,
        '');
    expect(
        tester
            .widget<TextField>(find.byKey(const Key('lyrics-input')))
            .controller!
            .text,
        '');
    expect(find.text('Ｄ Ｆ\n我 爱'), findsNothing);
    expect(find.text('转换结果将显示在这里'), findsOneWidget);
    expect(find.byKey(const Key('warning-text')), findsNothing);
    expect(find.byKey(const Key('error-text')), findsNothing);
    expect(find.byKey(const Key('unmatched-lyrics-text')), findsNothing);
    expect(container.read(conversionResultProvider), isNull);
    expect(container.read(converterInputProvider).scoreText, isEmpty);
    expect(container.read(converterInputProvider).lyricsText, isEmpty);
  });

  testWidgets('shows a locatable parse error after convert', (tester) async {
    await pumpPage(tester);

    await tester.enterText(find.byKey(const Key('score-input')), '3 4 5');
    await tester.pump();
    await tester.tap(find.byKey(const Key('convert-button')));
    await tester.pump();
    expect(find.text('Ｄ Ｆ Ｇ'), findsOneWidget);

    await tester.enterText(find.byKey(const Key('score-input')), '1#');
    await tester.pump();
    expect(find.text('Ｄ Ｆ Ｇ'), findsNothing);

    await tester.tap(find.byKey(const Key('convert-button')));
    await tester.pump();

    expect(find.text('第 1 行第 1 个元素无法识别：1#'), findsOneWidget);
    expect(find.text('位置：第 1 行，第 1 列'), findsOneWidget);
    expect(find.text('Ｄ Ｆ Ｇ'), findsNothing);
  });

  testWidgets('shows where lyrics are missing', (tester) async {
    await pumpPage(tester);

    await tester.enterText(find.byKey(const Key('score-input')), '3 0 4');
    await tester.enterText(find.byKey(const Key('lyrics-input')), '我');
    await tester.tap(find.byKey(const Key('convert-button')));
    await tester.pump();

    expect(
      find.text('缺少歌词的位置：第 1 行第 3 个元素'),
      findsOneWidget,
    );
  });

  testWidgets('loads the basic example into the two input fields',
      (tester) async {
    await pumpPage(tester);

    await tester.tap(find.byKey(const Key('load-example-button')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('填入两个输入框').first);
    await tester.pumpAndSettle();

    expect(
      tester
          .widget<TextField>(find.byKey(const Key('score-input')))
          .controller!
          .text,
      '1, 2, 3 0 4 | 5 6\' 7\' -',
    );
    expect(
      tester
          .widget<TextField>(find.byKey(const Key('lyrics-input')))
          .controller!
          .text,
      '微 风 来 | 到 身 边 -',
    );
  });

  testWidgets('opens format help from the converter page', (tester) async {
    await pumpPage(tester);

    await tester.tap(find.byKey(const Key('format-help-button')));
    await tester.pumpAndSettle();

    expect(find.text('格式说明'), findsOneWidget);
    expect(find.text('支持语法'), findsOneWidget);
    expect(find.text('默认键位'), findsOneWidget);
  });

  testWidgets('round trips text and grid modes without losing score or lyrics',
      (tester) async {
    final preferences = _PreferencesFake();
    final container = ProviderContainer(overrides: [
      converterDraftPersistenceProvider.overrideWithValue(
        ConverterDraftPersistence(preferences: preferences),
      ),
      recoverySnapshotRepositoryProvider.overrideWithValue(testSnapshots()),
    ]);
    try {
      await pumpPage(tester, container: container);
      await tester.enterText(find.byKey(const Key('score-input')), '3 4');
      await tester.enterText(find.byKey(const Key('lyrics-input')), '晨 光');
      await tester.tap(find.text('智能表格'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, '导入'));
      await tester.pumpAndSettle();

      expect(container.read(editorModeProvider), ConverterEditorMode.grid);
      expect(
          container.read(smartGridDocumentProvider).rows[0].cells, ['3', '4']);
      expect(
          container.read(smartGridDocumentProvider).rows[1].cells, ['晨', '光']);

      await tester.tap(find.text('文本输入'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, '切换'));
      await tester.pumpAndSettle();

      expect(container.read(editorModeProvider), ConverterEditorMode.text);
      expect(
        tester
            .widget<TextField>(find.byKey(const Key('score-input')))
            .controller!
            .text,
        '[谱] 3 4;\n[词] 晨 光;',
      );
      expect(
        tester
            .widget<TextField>(find.byKey(const Key('lyrics-input')))
            .controller!
            .text,
        isEmpty,
      );

      await tester.tap(find.text('智能表格'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, '导入'));
      await tester.pumpAndSettle();

      expect(container.read(editorModeProvider), ConverterEditorMode.grid);
      expect(
          container.read(smartGridDocumentProvider).rows[0].cells, ['3', '4']);
      expect(
          container.read(smartGridDocumentProvider).rows[1].cells, ['晨', '光']);
    } finally {
      try {
        await tester.pumpWidget(const SizedBox.shrink());
      } finally {
        container.dispose();
      }
    }
  });

  testWidgets('restores input after clearing when undo is selected',
      (tester) async {
    await pumpPage(tester);
    await tester.enterText(find.byKey(const Key('score-input')), '3 4 5');
    await tester.tap(find.byKey(const Key('clear-button')));
    await tester.pump();
    await tester.tap(find.text('清空').last);
    await tester.pump();
    tester.widget<SnackBarAction>(find.byType(SnackBarAction)).onPressed();
    await tester.pump();

    expect(
      tester
          .widget<TextField>(find.byKey(const Key('score-input')))
          .controller!
          .text,
      '3 4 5',
    );
  });
}

class _PreferencesFake extends Fake implements SharedPreferencesAsync {
  final Map<String, String> values = {};

  @override
  Future<String?> getString(String key) async => values[key];

  @override
  Future<void> setString(String key, String value) async {
    values[key] = value;
  }

  @override
  Future<void> remove(String key) async {
    values.remove(key);
  }
}

class _RecoverySnapshotsFake extends RecoverySnapshotRepository {
  @override
  Future<RecoverySnapshot?> create({
    required RecoverySnapshotType type,
    required Object? payload,
    required RecoverySnapshotSource source,
    String? note,
    bool deduplicate = false,
  }) async =>
      null;

  @override
  Future<void> flush() async {}
}
