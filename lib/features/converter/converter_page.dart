import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models/lyric_line.dart';
import '../../core/models/source_position.dart';
import 'converter_providers.dart';
import 'mapping_page.dart';

class ConverterPage extends ConsumerStatefulWidget {
  const ConverterPage({super.key});

  @override
  ConsumerState<ConverterPage> createState() => _ConverterPageState();
}

class _ConverterPageState extends ConsumerState<ConverterPage> {
  late final TextEditingController _scoreController;
  late final TextEditingController _lyricsController;

  @override
  void initState() {
    super.initState();
    _scoreController = TextEditingController();
    _lyricsController = TextEditingController();
  }

  @override
  void dispose() {
    _scoreController.dispose();
    _lyricsController.dispose();
    super.dispose();
  }

  void _convert() {
    ref
        .read(converterInputProvider.notifier)
        .setScoreText(_scoreController.text);
    ref
        .read(converterInputProvider.notifier)
        .setLyricsText(_lyricsController.text);
    ref.read(conversionResultProvider.notifier).convert();
  }

  void _clear() {
    _scoreController.clear();
    _lyricsController.clear();
    ref.read(converterInputProvider.notifier).clear();
  }

  Future<void> _copyOutput() async {
    final result = ref.read(conversionResultProvider);
    final output = result?.output ?? '';
    if (result == null || output.trim().isEmpty || result.hasErrors) {
      _showMessage('没有可复制的内容');
      return;
    }
    await Clipboard.setData(ClipboardData(text: output));
    if (!mounted) {
      return;
    }
    _showMessage('已复制到剪贴板');
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final result = ref.watch(conversionResultProvider);
    final mappingMessage = ref.watch(mappingPersistenceMessageProvider);
    final output = result?.output ?? '';

    return Scaffold(
      appBar: AppBar(
        title: const Text('数字简谱键盘字母转换器'),
        actions: [
          IconButton(
            key: const Key('open-mapping-button'),
            tooltip: '键盘映射',
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (context) => const MappingPage(),
                ),
              );
            },
            icon: const Icon(Icons.keyboard),
          ),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            if (mappingMessage != null) ...[
              Text(
                mappingMessage,
                key: const Key('mapping-persistence-message'),
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
              const SizedBox(height: 12),
            ],
            TextField(
              key: const Key('score-input'),
              controller: _scoreController,
              minLines: 6,
              maxLines: 12,
              keyboardType: TextInputType.multiline,
              decoration: const InputDecoration(
                labelText: '数字简谱',
                alignLabelWithHint: true,
                hintText: '3 4 5 6 7\n或使用 [谱] / [词] 标准格式',
                border: OutlineInputBorder(),
              ),
              onChanged: (value) {
                ref.read(converterInputProvider.notifier).setScoreText(value);
              },
            ),
            const SizedBox(height: 12),
            TextField(
              key: const Key('lyrics-input'),
              controller: _lyricsController,
              minLines: 3,
              maxLines: 8,
              keyboardType: TextInputType.multiline,
              decoration: const InputDecoration(
                labelText: '歌词（可选）',
                alignLabelWithHint: true,
                hintText: '我 爱 你',
                border: OutlineInputBorder(),
              ),
              onChanged: (value) {
                ref.read(converterInputProvider.notifier).setLyricsText(value);
              },
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                FilledButton(
                  key: const Key('convert-button'),
                  onPressed: _convert,
                  child: const Text('转换'),
                ),
                FilledButton.tonal(
                  key: const Key('copy-button'),
                  onPressed: _copyOutput,
                  child: const Text('复制'),
                ),
                OutlinedButton(
                  key: const Key('clear-button'),
                  onPressed: _clear,
                  child: const Text('清空'),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Text(
              '字母简谱',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                border: Border.all(
                  color: Theme.of(context).colorScheme.outlineVariant,
                ),
                borderRadius: BorderRadius.circular(8),
              ),
              child: SelectableText(
                key: const Key('output-text'),
                output.isEmpty ? '转换结果将显示在这里' : output,
                style: const TextStyle(
                  fontFamily: 'NSimSun',
                  fontFamilyFallback: [
                    'SimSun',
                    'MS Gothic',
                    'Consolas',
                    'monospace',
                  ],
                  fontSize: 16,
                  height: 1.5,
                ),
              ),
            ),
            if (result != null && result.hasErrors) ...[
              const SizedBox(height: 12),
              ...result.errors.map(
                (error) => Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Text(
                    error.message,
                    key: const Key('error-text'),
                    style:
                        TextStyle(color: Theme.of(context).colorScheme.error),
                  ),
                ),
              ),
              ...result.errors.map(
                (error) => Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Text(
                    '位置：第 ${error.line} 行，第 ${error.column} 列',
                    key: Key('error-location-${error.line}-${error.column}'),
                  ),
                ),
              ),
            ],
            if (result != null && result.hasWarnings) ...[
              const SizedBox(height: 12),
              ...result.warnings.map(
                (warning) => Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Text(
                    warning.message,
                    key: const Key('warning-text'),
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.tertiary,
                    ),
                  ),
                ),
              ),
            ],
            if (result != null && result.unmatchedLyrics.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text(
                '未匹配歌词：${_formatUnmatchedLyrics(result.unmatchedLyricTokens)}',
                key: const Key('unmatched-lyrics-text'),
                style: TextStyle(
                  color: Theme.of(context).colorScheme.tertiary,
                ),
              ),
            ],
            if (result != null &&
                result.missingLyricNotePositions.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text(
                '缺少歌词的位置：${_formatMissingLyricNotes(result.missingLyricNotePositions)}',
                key: const Key('missing-lyrics-position-text'),
                style: TextStyle(
                  color: Theme.of(context).colorScheme.tertiary,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

String _formatUnmatchedLyrics(List<LyricToken> tokens) => tokens
    .map((token) =>
        '${token.rawText}（第 ${token.line} 行第 ${token.elementIndex} 项）')
    .join(' ');

String _formatMissingLyricNotes(List<SourcePosition> positions) => positions
    .map((position) => '第 ${position.line} 行第 ${position.tokenIndex} 个元素')
    .join('、');
