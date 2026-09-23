import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models/lyric_line.dart';
import '../../core/models/source_position.dart';
import '../../core/renderer/share_image_text_renderer.dart';
import 'converter_examples.dart';
import 'converter_input.dart';
import 'converter_providers.dart';
import 'format_help_page.dart';
import 'mapping_page.dart';
import 'png_export_service.dart';
import 'semicolon_line_break_formatter.dart';
import '../library/song_library_page.dart';
import '../library/song_library_providers.dart';
import '../library/song_record.dart';

class ConverterPage extends ConsumerStatefulWidget {
  const ConverterPage({super.key});

  @override
  ConsumerState<ConverterPage> createState() => _ConverterPageState();
}

class _ConverterPageState extends ConsumerState<ConverterPage> {
  late final TextEditingController _scoreController;
  late final TextEditingController _lyricsController;
  final _outputImageKey = GlobalKey();
  var _isPreparingImageExport = false;

  @override
  void initState() {
    super.initState();
    final input = ref.read(converterInputProvider);
    _scoreController = TextEditingController(text: input.scoreText);
    _lyricsController = TextEditingController(text: input.lyricsText);
    if (ref.read(initialDraftRestoredProvider)) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _showMessage('已恢复上次草稿');
      });
    }
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

  Future<void> _clear() async {
    if (_scoreController.text.isNotEmpty || _lyricsController.text.isNotEmpty) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('清空输入？'),
          content: const Text('这会删除当前输入和已保存草稿。'),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('取消')),
            FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('清空')),
          ],
        ),
      );
      if (confirmed != true || !mounted) return;
    }
    final previous = ref.read(converterInputProvider.notifier).clear();
    ref.read(currentSongIdProvider.notifier).set(null);
    _scoreController.clear();
    _lyricsController.clear();
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: const Text('已清空输入和草稿'),
          duration: const Duration(seconds: 5),
          action: SnackBarAction(
            label: '撤销',
            onPressed: () {
              ref.read(converterInputProvider.notifier).restore(previous);
              _syncControllers(previous);
            },
          ),
        ),
      );
  }

  Future<void> _openLibrary() async {
    final action = await Navigator.of(context).push<SongLoadRequest>(
      MaterialPageRoute(
          builder: (_) =>
              SongLibraryPage(currentSongId: ref.read(currentSongIdProvider))),
    );
    if (action == null || !mounted) return;
    final current = ref.read(converterInputProvider);
    if ((current.scoreText.isNotEmpty || current.lyricsText.isNotEmpty) &&
        (current.scoreText != action.song.input.scoreText ||
            current.lyricsText != action.song.input.lyricsText)) {
      final accepted = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
                  title: const Text('替换当前输入？'),
                  content: const Text('当前尚未保存的输入将被曲谱库内容替换。'),
                  actions: [
                    TextButton(
                        onPressed: () => Navigator.pop(context, false),
                        child: const Text('取消')),
                    FilledButton(
                        onPressed: () => Navigator.pop(context, true),
                        child: const Text('替换'))
                  ]));
      if (accepted != true || !mounted) return;
    }
    ref.read(converterInputProvider.notifier).restore(action.song.input);
    ref.read(currentSongIdProvider.notifier).set(action.song.id);
    _syncControllers(action.song.input);
    _showMessage('已填入“${action.song.title}”');
  }

  Future<void> _saveToLibrary({bool forceCopy = false}) async {
    final input = ConverterInput(
        scoreText: _scoreController.text, lyricsText: _lyricsController.text);
    final library = ref.read(songLibraryProvider);
    final linkedId = forceCopy ? null : ref.read(currentSongIdProvider);
    final existing = linkedId == null ? null : _songById(library, linkedId);
    final fields = await _showSongDialog(existing);
    if (fields == null || !mounted) return;
    final now = DateTime.now().toUtc();
    final result = ref.read(conversionResultProvider);
    final mapping = ref.read(mappingDraftProvider).validate().mapping;
    final snapshot = result != null && !result.hasErrors && mapping != null
        ? SongResultSnapshot(
            output: result.output,
            mapping: mapping.toJson(),
            warnings: result.warnings.map((item) => item.message).toList(),
            savedAt: now)
        : null;
    final id = existing?.id ?? newSongId();
    final record = SongRecord(
        id: id,
        title: fields.title,
        artist: fields.artist,
        tags: fields.tags,
        notes: fields.notes,
        input: input,
        result: snapshot ?? existing?.result,
        resultIsStale: snapshot == null && existing?.result != null,
        createdAt: existing?.createdAt ?? now,
        updatedAt: now);
    try {
      await ref.read(songLibraryProvider.notifier).saveRecord(record);
      ref.read(currentSongIdProvider.notifier).set(id);
      await ref.read(converterDraftPersistenceProvider).save(input, songId: id);
      if (mounted) _showMessage(snapshot == null ? '已保存输入草稿' : '已保存曲谱和转换结果');
    } on Object {
      if (mounted) _showMessage('保存到曲谱库失败，请重试');
    }
  }

  Future<_SongFields?> _showSongDialog(SongRecord? existing) async {
    final title = TextEditingController(text: existing?.title ?? '');
    final artist = TextEditingController(text: existing?.artist ?? '');
    final notes = TextEditingController(text: existing?.notes ?? '');
    final tags = <String>[...?existing?.tags];
    final tagInput = TextEditingController();
    final suggestions = {
      for (final song in ref.read(songLibraryProvider)) ...song.tags
    }.toList()
      ..sort();
    try {
      return await showDialog<_SongFields>(
          context: context,
          builder: (context) => StatefulBuilder(
              builder: (context, setDialogState) => AlertDialog(
                    title: Text(existing == null ? '保存到曲谱库' : '保存修改'),
                    content: SizedBox(
                        width: 420,
                        child: SingleChildScrollView(
                            child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                              TextField(
                                  controller: title,
                                  autofocus: true,
                                  decoration: const InputDecoration(
                                      labelText: '歌曲名 *')),
                              TextField(
                                  controller: artist,
                                  decoration:
                                      const InputDecoration(labelText: '歌手')),
                              TextField(
                                  controller: tagInput,
                                  decoration: const InputDecoration(
                                      labelText: '标签（输入后按回车）'),
                                  onSubmitted: (value) {
                                    final tag = value.trim();
                                    if (tag.isNotEmpty && !tags.contains(tag))
                                      setDialogState(() => tags.add(tag));
                                    tagInput.clear();
                                  }),
                              if (tags.isNotEmpty)
                                Align(
                                    alignment: Alignment.centerLeft,
                                    child: Wrap(spacing: 4, children: [
                                      for (final tag in tags)
                                        InputChip(
                                            label: Text(tag),
                                            onDeleted: () => setDialogState(
                                                () => tags.remove(tag)))
                                    ])),
                              if (suggestions.isNotEmpty)
                                Align(
                                    alignment: Alignment.centerLeft,
                                    child: Wrap(spacing: 4, children: [
                                      for (final tag in suggestions
                                          .where((tag) => !tags.contains(tag)))
                                        ActionChip(
                                            label: Text(tag),
                                            onPressed: () => setDialogState(
                                                () => tags.add(tag)))
                                    ])),
                              TextField(
                                  controller: notes,
                                  maxLines: 3,
                                  decoration:
                                      const InputDecoration(labelText: '备注')),
                            ]))),
                    actions: [
                      TextButton(
                          onPressed: () => Navigator.pop(context),
                          child: const Text('取消')),
                      FilledButton(
                          onPressed: () {
                            if (title.text.trim().isEmpty) return;
                            Navigator.pop(
                                context,
                                _SongFields(
                                    title.text.trim(),
                                    artist.text.trim(),
                                    List.unmodifiable(tags),
                                    notes.text.trim()));
                          },
                          child: const Text('保存'))
                    ],
                  )));
    } finally {
      title.dispose();
      artist.dispose();
      notes.dispose();
      tagInput.dispose();
    }
  }

  Future<void> _showExamples() async {
    final choice = await showModalBottomSheet<_ExampleSelection>(
      context: context,
      builder: (context) => ListView(
        shrinkWrap: true,
        padding: const EdgeInsets.all(16),
        children: [
          Text('载入示例', style: Theme.of(context).textTheme.titleLarge),
          for (final example in converterExamples) ...[
            const SizedBox(height: 12),
            Text(example.title, style: Theme.of(context).textTheme.titleMedium),
            Text(example.description),
            Wrap(
              spacing: 8,
              children: [
                TextButton(
                  onPressed: () =>
                      Navigator.pop(context, _ExampleSelection(example, false)),
                  child: const Text('填入两个输入框'),
                ),
                TextButton(
                  onPressed: () =>
                      Navigator.pop(context, _ExampleSelection(example, true)),
                  child: const Text('填入标准文档'),
                ),
              ],
            ),
          ],
        ],
      ),
    );
    if (choice == null || !mounted) return;
    await _applyExample(choice.example,
        standardDocument: choice.standardDocument);
  }

  Future<void> _applyExample(
    ConverterExample example, {
    bool standardDocument = false,
  }) async {
    if (_scoreController.text.isNotEmpty || _lyricsController.text.isNotEmpty) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('替换当前输入？'),
          content: const Text('载入示例会替换当前正在编辑的内容。'),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('取消')),
            FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('替换')),
          ],
        ),
      );
      if (confirmed != true || !mounted) return;
    }
    final input = standardDocument
        ? ConverterInput(scoreText: example.standardDocument)
        : example.input;
    ref.read(converterInputProvider.notifier).replace(input);
    _syncControllers(input);
  }

  Future<void> _exportImage() async {
    final result = ref.read(conversionResultProvider);
    if (result == null || result.hasErrors) {
      _showMessage('没有可导出的内容');
      return;
    }
    setState(() => _isPreparingImageExport = true);
    await WidgetsBinding.instance.endOfFrame;
    try {
      final boundary = _outputImageKey.currentContext?.findRenderObject()
          as RenderRepaintBoundary?;
      if (boundary == null) throw StateError('无法生成图片');
      final image = await boundary.toImage(pixelRatio: 3);
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      image.dispose();
      if (data == null) throw StateError('无法生成图片');
      final savedPath =
          await const PngExportService().export(data.buffer.asUint8List());
      if (!mounted) return;
      _showMessage(savedPath == null ? '已取消导出' : '图片已保存');
    } on Object {
      if (mounted) _showMessage('导出图片失败，请重试。');
    } finally {
      if (mounted) {
        setState(() => _isPreparingImageExport = false);
      }
    }
  }

  void _syncControllers(ConverterInput input) {
    if (_scoreController.text != input.scoreText) {
      _scoreController.text = input.scoreText;
    }
    if (_lyricsController.text != input.lyricsText) {
      _lyricsController.text = input.lyricsText;
    }
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
    ref.watch(converterInputProvider);
    final result = ref.watch(conversionResultProvider);
    final mappingMessage = ref.watch(mappingPersistenceMessageProvider);
    final currentSongId = ref.watch(currentSongIdProvider);
    final currentSong = currentSongId == null
        ? null
        : _songById(ref.watch(songLibraryProvider), currentSongId);
    final draftMessage = ref.watch(draftPersistenceMessageProvider);
    final output = result?.output ?? '';
    final imageOutput = switch (result?.score) {
      final score? => const ShareImageTextRenderer().render(score),
      null => output,
    };

    return Scaffold(
      appBar: AppBar(
        title: const Text('数字简谱键盘字母转换器'),
        actions: [
          IconButton(
              key: const Key('open-song-library-button'),
              tooltip: '曲谱库',
              onPressed: _openLibrary,
              icon: const Icon(Icons.library_music)),
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
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (draftMessage != null) ...[
                  Text(draftMessage,
                      style: TextStyle(
                          color: Theme.of(context).colorScheme.error)),
                  const SizedBox(height: 12),
                ],
                if (mappingMessage != null) ...[
                  Text(
                    mappingMessage,
                    key: const Key('mapping-persistence-message'),
                    style:
                        TextStyle(color: Theme.of(context).colorScheme.error),
                  ),
                  const SizedBox(height: 12),
                ],
                TextField(
                  key: const Key('score-input'),
                  controller: _scoreController,
                  inputFormatters: const [SemicolonLineBreakFormatter()],
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
                    ref
                        .read(converterInputProvider.notifier)
                        .setScoreText(value);
                  },
                ),
                const SizedBox(height: 12),
                TextField(
                  key: const Key('lyrics-input'),
                  controller: _lyricsController,
                  inputFormatters: const [SemicolonLineBreakFormatter()],
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
                    ref
                        .read(converterInputProvider.notifier)
                        .setLyricsText(value);
                  },
                ),
                const SizedBox(height: 12),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Wrap(
                    spacing: 8,
                    children: [
                      TextButton(
                          key: const Key('load-example-button'),
                          onPressed: _showExamples,
                          child: const Text('载入示例')),
                      TextButton(
                        key: const Key('format-help-button'),
                        onPressed: () {
                          Navigator.of(context).push(MaterialPageRoute<void>(
                            builder: (context) => FormatHelpPage(
                              onUseExample: (example) {
                                Navigator.of(context).pop();
                                _applyExample(example);
                              },
                            ),
                          ));
                        },
                        child: const Text('格式说明'),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 4),
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
                    FilledButton.tonal(
                      key: const Key('export-image-button'),
                      onPressed:
                          result == null || result.hasErrors || output.isEmpty
                              ? null
                              : _exportImage,
                      child: const Text('导出图片'),
                    ),
                    FilledButton.tonal(
                      key: const Key('save-song-button'),
                      onPressed: () => _saveToLibrary(),
                      child: Text(currentSong == null ? '保存到曲谱库' : '保存修改'),
                    ),
                    if (currentSong != null)
                      OutlinedButton(
                        onPressed: () => _saveToLibrary(forceCopy: true),
                        child: const Text('另存为'),
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
                RepaintBoundary(
                  key: _outputImageKey,
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.surface,
                      border: Border.all(
                          color: Theme.of(context).colorScheme.outlineVariant),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: _isPreparingImageExport
                        ? SelectableText(
                            imageOutput.isEmpty ? '转换结果将显示在这里' : imageOutput,
                            style: _outputTextStyle,
                          )
                        : SingleChildScrollView(
                            scrollDirection: Axis.horizontal,
                            child: SelectableText(
                              key: const Key('output-text'),
                              output.isEmpty ? '转换结果将显示在这里' : output,
                              style: _outputTextStyle,
                            ),
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
                        style: TextStyle(
                            color: Theme.of(context).colorScheme.error),
                      ),
                    ),
                  ),
                  ...result.errors.map(
                    (error) => Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: Text(
                        '位置：第 ${error.line} 行，第 ${error.column} 列',
                        key:
                            Key('error-location-${error.line}-${error.column}'),
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
        ),
      ),
    );
  }
}

const _outputTextStyle = TextStyle(
  fontFamily: 'NSimSun',
  fontFamilyFallback: ['SimSun', 'MS Gothic', 'Consolas', 'monospace'],
  fontSize: 16,
  height: 1.5,
);

class _ExampleSelection {
  final ConverterExample example;
  final bool standardDocument;

  const _ExampleSelection(this.example, this.standardDocument);
}

class _SongFields {
  final String title;
  final String artist;
  final List<String> tags;
  final String notes;
  const _SongFields(this.title, this.artist, this.tags, this.notes);
}

SongRecord? _songById(List<SongRecord> songs, String id) {
  for (final song in songs) {
    if (song.id == id) return song;
  }
  return null;
}

String _formatUnmatchedLyrics(List<LyricToken> tokens) => tokens
    .map((token) =>
        '${token.rawText}（第 ${token.line} 行第 ${token.elementIndex} 项）')
    .join(' ');

String _formatMissingLyricNotes(List<SourcePosition> positions) => positions
    .map((position) => '第 ${position.line} 行第 ${position.tokenIndex} 个元素')
    .join('、');
