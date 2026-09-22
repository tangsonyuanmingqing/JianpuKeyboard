import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'converter_examples.dart';

class FormatHelpPage extends StatelessWidget {
  final ValueChanged<ConverterExample> onUseExample;

  const FormatHelpPage({super.key, required this.onUseExample});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('格式说明')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text('支持语法', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 8),
          const Text(
              '中音：1 2 3 4 5 6 7\n高音：1\' 2\' 3\'\n低音：1, 2, 3,\n0 为休止，- 为延音，| 为小节线。\n\n可重复写 [谱]、[词] 区块；// 表示一句结束，; 表示一行结束。按 Enter 会自动补上 ;。'),
          const SizedBox(height: 20),
          Text('默认键位', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 8),
          const SelectableText(
              '低音：Z X C V B N M\n中音：A S D F G H J\n高音：Q W E R T Y U'),
          const SizedBox(height: 20),
          Text('歌词对齐', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 8),
          const Text(
              '普通歌词按顺序对应音符。歌词 - 表示延续上一个歌词；谱面中的 0、- 和 | 不消耗歌词。每个 [谱] 与其后的 [词] 就近配对；谱词都可用 // 分句、用 ; 分行。'),
          const SizedBox(height: 20),
          Text('示例', style: Theme.of(context).textTheme.titleLarge),
          for (final example in converterExamples)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(example.title,
                        style: Theme.of(context).textTheme.titleMedium),
                    const SizedBox(height: 4),
                    Text(example.description),
                    const SizedBox(height: 8),
                    TextButton(
                      onPressed: () async {
                        await Clipboard.setData(
                            ClipboardData(text: example.standardDocument));
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('示例已复制到剪贴板')),
                          );
                        }
                      },
                      child: const Text('复制示例'),
                    ),
                    TextButton(
                      onPressed: () => onUseExample(example),
                      child: const Text('使用此示例'),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}
