import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jianpu_keyboard/features/converter/converter_page.dart';
import 'package:jianpu_keyboard/features/converter/converter_providers.dart';

void main() {
  Future<void> pumpPage(
    WidgetTester tester, {
    ProviderContainer? container,
  }) async {
    final Widget app = container == null
        ? const ProviderScope(
            child: MaterialApp(home: ConverterPage()),
          )
        : UncontrolledProviderScope(
            container: container,
            child: const MaterialApp(home: ConverterPage()),
          );
    await tester.pumpWidget(app);
  }

  testWidgets('does not convert score input automatically', (tester) async {
    await pumpPage(tester);

    await tester.enterText(find.byKey(const Key('score-input')), '3 4 5');
    await tester.pump();

    expect(find.text('D F G'), findsNothing);
    expect(find.text('转换结果将显示在这里'), findsOneWidget);
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

    expect(find.text('D F G'), findsOneWidget);
  });

  testWidgets('clears the previous result when input changes', (tester) async {
    await pumpPage(tester);

    await tester.enterText(find.byKey(const Key('score-input')), '3 4 5');
    await tester.pump();
    await tester.tap(find.byKey(const Key('convert-button')));
    await tester.pump();
    expect(find.text('D F G'), findsOneWidget);

    await tester.enterText(find.byKey(const Key('score-input')), '3 4 5 6');
    await tester.pump();

    expect(find.text('D F G'), findsNothing);
    expect(find.text('D F G H'), findsNothing);
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
      'D  F  G\n我 爱 你',
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

    expect(clipboardText, 'D F G');
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
      'D  S  S -\n低 垂 -',
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

    expect(clipboardText, 'D  F\n我 爱');
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

    expect(find.text('D  F\n我 爱'), findsOneWidget);
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
    expect(find.text('D  F\n我 爱'), findsNothing);
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
    expect(find.text('D F G'), findsOneWidget);

    await tester.enterText(find.byKey(const Key('score-input')), '1#');
    await tester.pump();
    expect(find.text('D F G'), findsNothing);

    await tester.tap(find.byKey(const Key('convert-button')));
    await tester.pump();

    expect(find.text('第 1 行第 1 个元素无法识别：1#'), findsOneWidget);
    expect(find.text('位置：第 1 行，第 1 列'), findsOneWidget);
    expect(find.text('D F G'), findsNothing);
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
