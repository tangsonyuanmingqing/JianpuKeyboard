import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme/app_typography.dart';
import '../../app/theme/app_theme_mode.dart';
import '../../app/window/window_pin.dart';
import '../../infrastructure/storage_health.dart';
import '../../core/models/lyric_line.dart';
import '../../core/models/source_position.dart';
import '../../core/renderer/share_image_text_renderer.dart';
import 'converter_examples.dart';
import 'converter_input.dart';
import 'converter_panel_layout_persistence.dart';
import 'converter_providers.dart';
import 'format_help_page.dart';
import 'mapping_page.dart';
import 'png_export_service.dart';
import 'resizable_panel.dart';
import 'semicolon_line_break_formatter.dart';
import 'song_output_formatter.dart';
import 'smart_grid_codec.dart';
import 'smart_grid_converter.dart';
import 'smart_grid_document.dart';
import 'smart_grid_editor.dart';
import 'smart_grid_inspection_renderer.dart';
import 'smart_grid_validation.dart';
import 'table_scale.dart';
import '../library/song_library_page.dart';
import '../library/recovery_center_page.dart';
import '../library/song_library_providers.dart';
import '../library/song_record.dart';

class ConverterPage extends ConsumerStatefulWidget {
  const ConverterPage({super.key});

  @override
  ConsumerState<ConverterPage> createState() => _ConverterPageState();
}

class _ConverterPageState extends ConsumerState<ConverterPage>
    with WidgetsBindingObserver {
  late final TextEditingController _scoreController;
  late final TextEditingController _lyricsController;
  late final TextEditingController _songTitleController;
  final FocusNode _scoreFocusNode = FocusNode();
  final _outputImageKey = GlobalKey();
  final _gridEditorKey = GlobalKey<SmartGridEditorState>();
  late final ConverterPanelLayoutPersistence _panelLayoutPersistence;
  Map<String, ResizablePanelSize> _panelSizes = const {};
  var _isPreparingImageExport = false;
  SmartGridConversion? _gridConversion;
  SmartGridDocument? _gridConversionDocument;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    final input = ref.read(converterInputProvider);
    _scoreController = TextEditingController(text: input.scoreText);
    _lyricsController = TextEditingController(text: input.lyricsText);
    _songTitleController =
        TextEditingController(text: ref.read(songTitleProvider));
    _panelLayoutPersistence = ref.read(converterPanelLayoutPersistenceProvider);
    unawaited(_restorePanelLayout());
    if (ref.read(editorModeProvider) == ConverterEditorMode.grid &&
        ref.read(smartGridDocumentProvider).isEmpty &&
        (input.scoreText.isNotEmpty || input.lyricsText.isNotEmpty)) {
      final imported = const SmartGridCodec().importInput(input);
      if (imported.isValid) {
        ref
            .read(smartGridDocumentProvider.notifier)
            .replaceWithoutInput(imported.document!);
      }
    }
    if (ref.read(initialDraftRestoredProvider)) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _showMessage('已恢复上次草稿');
      });
    }
  }

  Future<void> _restorePanelLayout() async {
    final saved = await _panelLayoutPersistence.load();
    if (!mounted || saved.isEmpty) return;
    setState(() => _panelSizes = saved);
  }

  ResizablePanelSize _panelSize(String panelId) =>
      _panelSizes[panelId] ?? const ResizablePanelSize();

  void _updatePanelSize(String panelId, ResizablePanelSize size) {
    setState(() {
      final updated = Map<String, ResizablePanelSize>.of(_panelSizes);
      if (size.isDefault) {
        updated.remove(panelId);
      } else {
        updated[panelId] = size;
      }
      _panelSizes = updated;
    });
    unawaited(_panelLayoutPersistence.save(_panelSizes));
  }

  double _textInputDefaultHeight(BuildContext context) =>
      ((MediaQuery.sizeOf(context).height - 280) / 2)
          .clamp(ResizablePanel.minHeight, ResizablePanel.defaultHeight)
          .toDouble();

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _scoreController.dispose();
    _lyricsController.dispose();
    _songTitleController.dispose();
    _scoreFocusNode.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      unawaited(_persistDraftNow());
    }
  }

  Future<void> _persistDraftNow() async {
    try {
      await ref.read(converterInputProvider.notifier).flush();
    } on Object {
      // The regular draft saver displays the recoverable persistence error.
    }
  }

  void _convert() {
    if (ref.read(editorModeProvider) == ConverterEditorMode.grid) {
      final validation = ref.read(mappingDraftProvider).validate();
      if (!validation.isValid) {
        ref.read(conversionResultProvider.notifier).convert();
        return;
      }
      final converted = const SmartGridConverter().convert(
        ref.read(smartGridDocumentProvider),
        validation.mapping!,
      );
      setState(() {
        _gridConversion = converted;
        _gridConversionDocument = ref.read(smartGridDocumentProvider);
      });
      ref.read(conversionResultProvider.notifier).setResult(converted.result);
      return;
    }
    ref
        .read(converterInputProvider.notifier)
        .setScoreText(_scoreController.text);
    ref
        .read(converterInputProvider.notifier)
        .setLyricsText(_lyricsController.text);
    ref.read(conversionResultProvider.notifier).convert();
  }

  String get _songTitle => _songTitleController.text.trim();

  void _setSongTitle(String value) {
    if (_songTitleController.text != value) {
      _songTitleController.value = TextEditingValue(
        text: value,
        selection: TextSelection.collapsed(offset: value.length),
      );
    }
    ref.read(songTitleProvider.notifier).replace(value);
  }

  void _focusPrimaryEditor(String _) {
    if (ref.read(editorModeProvider) == ConverterEditorMode.grid) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _gridEditorKey.currentState?.focusCell(0, 0);
      });
      return;
    }
    FocusScope.of(context).requestFocus(_scoreFocusNode);
  }

  bool _hasUnsavedSongChanges(SongRecord? savedSong) {
    final mode = ref.read(editorModeProvider);
    final grid = ref.read(smartGridDocumentProvider);
    final input = mode == ConverterEditorMode.grid
        ? const SmartGridCodec().exportInput(grid)
        : ConverterInput(
            scoreText: _scoreController.text,
            lyricsText: _lyricsController.text,
          );
    if (savedSong == null) {
      return _songTitle.isNotEmpty ||
          input.scoreText.trim().isNotEmpty ||
          input.lyricsText.trim().isNotEmpty ||
          !grid.isEmpty;
    }
    return _songTitle != savedSong.title ||
        input != savedSong.input ||
        mode.name != savedSong.editorMode ||
        !_sameSongGridContent(grid, savedSong.gridDocument);
  }

  Future<void> _clear() async {
    final hasGridInput = !ref.read(smartGridDocumentProvider).isEmpty;
    if (_scoreController.text.isNotEmpty ||
        _lyricsController.text.isNotEmpty ||
        hasGridInput ||
        _songTitle.isNotEmpty ||
        ref.read(currentSongIdProvider) != null) {
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
    final previousGrid = ref.read(smartGridDocumentProvider);
    final previousSongId = ref.read(currentSongIdProvider);
    final previousTitle = _songTitleController.text;
    ref.read(smartGridDocumentProvider.notifier).clear();
    ref.read(currentSongIdProvider.notifier).set(null);
    _setSongTitle('');
    setState(() {
      _gridConversion = null;
      _gridConversionDocument = null;
    });
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
              ref.read(currentSongIdProvider.notifier).set(previousSongId);
              _setSongTitle(previousTitle);
              ref.read(converterInputProvider.notifier).restore(previous);
              ref
                  .read(smartGridDocumentProvider.notifier)
                  .replaceWithoutInput(previousGrid);
              _syncControllers(previous);
            },
          ),
        ),
      );
  }

  Future<void> _openLibrary() async {
    final action = await Navigator.of(context).push<Object?>(
      MaterialPageRoute<Object?>(
          builder: (_) =>
              SongLibraryPage(currentSongId: ref.read(currentSongIdProvider))),
    );
    if (action == null || !mounted) return;
    if (action is DraftRecoveryRequest) {
      final draft = action.draft;
      ref.read(currentSongIdProvider.notifier).set(draft.songId);
      ref.read(songTitleProvider.notifier).replace(draft.songTitle);
      _songTitleController.text = draft.songTitle;
      ref.read(smartGridDocumentProvider.notifier).replaceWithoutInput(
            draft.gridDocument ?? SmartGridDocument.empty(),
          );
      ref.read(editorModeProvider.notifier).set(
            draft.editorMode == 'grid'
                ? ConverterEditorMode.grid
                : ConverterEditorMode.text,
          );
      ref.read(converterInputProvider.notifier).restore(draft.input);
      _syncControllers(draft.input);
      setState(() {
        _gridConversion = null;
        _gridConversionDocument = null;
      });
      _showMessage('草稿已恢复，可以继续编辑');
      return;
    }
    if (action is! SongLoadRequest) return;
    final currentSongId = ref.read(currentSongIdProvider);
    final currentSong = currentSongId == null
        ? null
        : _songById(ref.read(songLibraryProvider), currentSongId);
    if (_hasUnsavedSongChanges(currentSong) &&
        action.song.id != currentSong?.id) {
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
    ref.read(currentSongIdProvider.notifier).set(action.song.id);
    _setSongTitle(action.song.title);
    if (action.song.gridDocument != null) {
      ref
          .read(smartGridDocumentProvider.notifier)
          .replaceWithoutInput(action.song.gridDocument!);
      ref.read(editorModeProvider.notifier).set(
            action.song.editorMode == 'grid'
                ? ConverterEditorMode.grid
                : ConverterEditorMode.text,
          );
    } else {
      final imported = const SmartGridCodec().importInput(action.song.input);
      if (imported.isValid) {
        ref
            .read(smartGridDocumentProvider.notifier)
            .replaceWithoutInput(imported.document!);
      }
      ref.read(editorModeProvider.notifier).set(ConverterEditorMode.text);
    }
    ref.read(converterInputProvider.notifier).restore(action.song.input);
    setState(() {
      _gridConversion = null;
      _gridConversionDocument = null;
    });
    _syncControllers(action.song.input);
    _showMessage('已填入“${action.song.title}”');
  }

  Future<void> _saveToLibrary({bool forceCopy = false}) async {
    final mode = ref.read(editorModeProvider);
    final input = mode == ConverterEditorMode.grid
        ? const SmartGridCodec()
            .exportInput(ref.read(smartGridDocumentProvider))
        : ConverterInput(
            scoreText: _scoreController.text,
            lyricsText: _lyricsController.text,
          );
    final library = ref.read(songLibraryProvider);
    final linkedId = ref.read(currentSongIdProvider);
    final source = linkedId == null ? null : _songById(library, linkedId);
    final existing = forceCopy ? null : source;
    final requiresTitle = _songTitle.isEmpty || forceCopy;
    final defaultTitle =
        forceCopy && _songTitle.isNotEmpty ? '$_songTitle - 副本' : _songTitle;
    final fields = await _showSongDialog(
      source: source,
      title: defaultTitle,
      includeTitle: requiresTitle,
      dialogTitle: forceCopy
          ? '另存为'
          : existing == null
              ? '保存到曲谱库'
              : '保存修改',
    );
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
        gridDocument: ref.read(smartGridDocumentProvider),
        editorMode: mode.name,
        result: snapshot ?? existing?.result,
        resultIsStale: snapshot == null && existing?.result != null,
        createdAt: existing?.createdAt ?? now,
        updatedAt: now);
    try {
      await ref.read(songLibraryProvider.notifier).saveRecord(record);
      ref.read(currentSongIdProvider.notifier).set(id);
      _setSongTitle(fields.title);
      await ref.read(converterInputProvider.notifier).flush();
      if (mounted) _showMessage(snapshot == null ? '已保存输入草稿' : '已保存曲谱和转换结果');
    } on Object {
      if (mounted) _showMessage('保存到曲谱库失败，请重试');
    }
  }

  Future<_SongFields?> _showSongDialog({
    required SongRecord? source,
    required String title,
    required bool includeTitle,
    required String dialogTitle,
  }) async {
    final suggestions = {
      for (final song in ref.read(songLibraryProvider)) ...song.tags
    }.toList()
      ..sort();
    return showDialog<_SongFields>(
      context: context,
      builder: (context) => _SongDialog(
        source: source,
        title: title,
        includeTitle: includeTitle,
        dialogTitle: dialogTitle,
        suggestions: suggestions,
      ),
    );
  }

  Future<void> _switchEditorMode(ConverterEditorMode nextMode) async {
    final current = ref.read(editorModeProvider);
    if (current == nextMode) return;
    if (nextMode == ConverterEditorMode.grid) {
      final input = ConverterInput(
        scoreText: _scoreController.text,
        lyricsText: _lyricsController.text,
      );
      final imported = const SmartGridCodec().importInput(input);
      if (!imported.isValid) {
        await showDialog<void>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('暂时无法转换为表格'),
            content: SingleChildScrollView(
              child: Text(imported.errors.take(8).join('\n')),
            ),
            actions: [
              FilledButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('返回修改'),
              ),
            ],
          ),
        );
        return;
      }
      if (!mounted) return;
      final document = imported.document!;
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('导入智能表格？'),
          content: SizedBox(
            width: 620,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  '将生成 ${document.rows.length} 行 × ${document.columnCount} 列的表格。原文本仍会保留为兼容格式。',
                ),
                const SizedBox(height: 12),
                _gridImportPreview(document),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('导入'),
            ),
          ],
        ),
      );
      if (confirmed != true || !mounted) return;
      ref
          .read(smartGridDocumentProvider.notifier)
          .replaceWithoutInput(document);
      ref.read(editorModeProvider.notifier).set(nextMode);
      ref.read(converterInputProvider.notifier).replace(
            const SmartGridCodec().exportInput(document),
          );
      setState(() {
        _gridConversion = null;
        _gridConversionDocument = null;
      });
      return;
    }
    final input = const SmartGridCodec().exportInput(
      ref.read(smartGridDocumentProvider),
    );
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('切换到文本输入？'),
        content: SizedBox(
          width: 620,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text('表格会转换成下面的项目扩展格式，可随时再导入智能表格。'),
              const SizedBox(height: 12),
              Container(
                constraints: const BoxConstraints(maxHeight: 260),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  border: Border.all(
                    color: Theme.of(context).colorScheme.outlineVariant,
                  ),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: SingleChildScrollView(
                  child: SelectableText(
                    input.scoreText,
                    style: AppTypography.of(context).notationBody,
                  ),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('切换'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    ref.read(editorModeProvider.notifier).set(nextMode);
    ref.read(converterInputProvider.notifier).replace(input);
    _syncControllers(input);
    setState(() {});
  }

  Widget _gridImportPreview(SmartGridDocument document) {
    final rows = document.rows.take(6).toList();
    return Container(
      constraints: const BoxConstraints(maxHeight: 230),
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerLowest,
        border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
        borderRadius: BorderRadius.circular(8),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (var index = 0; index < rows.length; index++)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 3),
                child: Text(
                  '${index + 1}  ${rows[index].type == SmartGridRowType.score ? '谱' : '词'}  '
                  '${rows[index].cells.map((cell) => cell.isEmpty ? '_' : cell).join('  ')}',
                ),
              ),
            if (document.rows.length > rows.length)
              Text('…另有 ${document.rows.length - rows.length} 行'),
          ],
        ),
      ),
    );
  }

  void _updateGrid(SmartGridDocument document) {
    ref.read(smartGridDocumentProvider.notifier).update(document);
    setState(() {});
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
    if (ref.read(editorModeProvider) == ConverterEditorMode.grid) {
      final imported = const SmartGridCodec().importInput(input);
      if (imported.isValid) {
        ref
            .read(smartGridDocumentProvider.notifier)
            .replaceWithoutInput(imported.document!);
      } else {
        ref.read(editorModeProvider.notifier).set(ConverterEditorMode.text);
      }
      setState(() {
        _gridConversion = null;
        _gridConversionDocument = null;
      });
    }
  }

  Future<void> _exportImage() async {
    final result = ref.read(conversionResultProvider) ??
        (ref.read(editorModeProvider) == ConverterEditorMode.grid
            ? _gridConversion?.result
            : null);
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
      final savedPath = await const PngExportService().export(
        data.buffer.asUint8List(),
        songTitle: _songTitle,
        imageType: '字母简谱',
      );
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

  Future<void> _exportInspectionImage() async {
    final conversion = _gridConversion;
    final document = _gridConversionDocument;
    if (conversion == null || document == null || conversion.result.hasErrors) {
      _showMessage('没有可导出的检查结果');
      return;
    }
    try {
      final bytes = await const SmartGridInspectionRenderer().render(
        document,
        conversion,
        songTitle: _songTitle,
      );
      final savedPath = await const PngExportService().export(
        bytes,
        songTitle: _songTitle,
        imageType: '检查图',
      );
      if (mounted) {
        _showMessage(savedPath == null ? '已取消导出' : '检查图已保存');
      }
    } on FormatException catch (error) {
      if (mounted) _showMessage(error.message);
    } on Object {
      if (mounted) _showMessage('导出检查图失败，请重试。');
    }
  }

  Widget _outputPanel(
    String value, {
    bool imageMode = false,
    double? width,
    String songTitle = '',
  }) {
    final typography = AppTypography.of(context);
    final contents = SelectableText(
      key: imageMode ? null : const Key('output-text'),
      value,
      style: typography.notationBody,
    );
    return RepaintBoundary(
      key: _outputImageKey,
      child: Container(
        width: width,
        constraints: imageMode ? null : const BoxConstraints.expand(),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          border:
              Border.all(color: Theme.of(context).colorScheme.outlineVariant),
          borderRadius: BorderRadius.circular(8),
        ),
        child: imageMode
            ? Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (songTitle.trim().isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Text(
                        songTitle.trim(),
                        textAlign: TextAlign.center,
                        style: typography.songTitle,
                      ),
                    ),
                  contents,
                ],
              )
            : SingleChildScrollView(
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: contents,
                ),
              ),
      ),
    );
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
    final result = ref.read(conversionResultProvider) ??
        (ref.read(editorModeProvider) == ConverterEditorMode.grid
            ? _gridConversion?.result
            : null);
    final output = result?.output ?? '';
    if (result == null || output.trim().isEmpty || result.hasErrors) {
      _showMessage('没有可复制的内容');
      return;
    }
    await Clipboard.setData(
      ClipboardData(text: formatSongOutput(_songTitle, output)),
    );
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
    final editorMode = ref.watch(editorModeProvider);
    final gridDocument = ref.watch(smartGridDocumentProvider);
    final displayedResult = result ??
        (editorMode == ConverterEditorMode.grid
            ? _gridConversion?.result
            : null);
    final mappingMessage = ref.watch(mappingPersistenceMessageProvider);
    final currentSongId = ref.watch(currentSongIdProvider);
    final currentSong = currentSongId == null
        ? null
        : _songById(ref.watch(songLibraryProvider), currentSongId);
    final songTitle = ref.watch(songTitleProvider);
    final tableScale = ref.watch(tableScaleProvider);
    final hasUnsavedSongChanges = _hasUnsavedSongChanges(currentSong);
    final draftMessage = ref.watch(draftPersistenceMessageProvider);
    final draftHealth = ref.watch(draftStorageHealthProvider);
    final draftWriteState = ref.watch(draftWriteStateProvider);
    final output = displayedResult?.output ?? '';
    final imageOutput = switch (displayedResult?.score) {
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
          const ThemeToggleButton(),
          const WindowPinToggleButton(),
        ],
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (draftHealth.blocksWrites) ...[
                  MaterialBanner(
                    content: Text(draftHealth.message ?? '草稿需要恢复。'),
                    actions: [
                      TextButton(
                        onPressed: () async {
                          final result =
                              await Navigator.of(context).push<Object?>(
                            MaterialPageRoute<Object?>(
                              builder: (_) => const RecoveryCenterPage(),
                            ),
                          );
                          if (result is DraftRecoveryRequest && mounted) {
                            final draft = result.draft;
                            ref
                                .read(currentSongIdProvider.notifier)
                                .set(draft.songId);
                            ref
                                .read(songTitleProvider.notifier)
                                .replace(draft.songTitle);
                            _songTitleController.text = draft.songTitle;
                            ref
                                .read(smartGridDocumentProvider.notifier)
                                .replaceWithoutInput(
                                  draft.gridDocument ??
                                      SmartGridDocument.empty(),
                                );
                            ref.read(editorModeProvider.notifier).set(
                                  draft.editorMode == 'grid'
                                      ? ConverterEditorMode.grid
                                      : ConverterEditorMode.text,
                                );
                            ref
                                .read(converterInputProvider.notifier)
                                .restore(draft.input);
                            _syncControllers(draft.input);
                          }
                        },
                        child: const Text('打开恢复中心'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                ],
                if (draftMessage != null) ...[
                  Text(
                    draftMessage,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: Theme.of(context).colorScheme.error,
                        ),
                  ),
                  const SizedBox(height: 12),
                ],
                if (mappingMessage != null) ...[
                  Text(
                    mappingMessage,
                    key: const Key('mapping-persistence-message'),
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: Theme.of(context).colorScheme.error,
                        ),
                  ),
                  const SizedBox(height: 12),
                ],
                Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 480),
                    child: TextField(
                      key: const Key('song-title-input'),
                      controller: _songTitleController,
                      maxLength: 80,
                      textInputAction: TextInputAction.next,
                      onSubmitted: _focusPrimaryEditor,
                      decoration: const InputDecoration(
                        labelText: '歌曲名',
                        hintText: '输入歌曲名',
                        border: OutlineInputBorder(),
                      ),
                      onChanged: (value) =>
                          ref.read(songTitleProvider.notifier).update(value),
                    ),
                  ),
                ),
                Align(
                  alignment: Alignment.center,
                  child: Text(
                    switch (draftWriteState.phase) {
                      PersistenceWritePhase.saving => '草稿保存中…',
                      PersistenceWritePhase.saved => '草稿已保存',
                      PersistenceWritePhase.failed => '草稿保存失败，可点击重试',
                      PersistenceWritePhase.idle => '',
                    },
                    key: const Key('draft-save-status'),
                  ),
                ),
                if (draftWriteState.phase == PersistenceWritePhase.failed)
                  Center(
                    child: TextButton(
                      onPressed: () =>
                          ref.read(converterInputProvider.notifier).retry(),
                      child: const Text('重试保存'),
                    ),
                  ),
                if (hasUnsavedSongChanges)
                  const Align(
                    alignment: Alignment.center,
                    child: Padding(
                      padding: EdgeInsets.only(bottom: 8),
                      child: Chip(
                        avatar: Icon(Icons.edit_note, size: 18),
                        label: Text('待保存到曲谱库'),
                        visualDensity: VisualDensity.compact,
                      ),
                    ),
                  ),
                Align(
                  alignment: Alignment.centerLeft,
                  child: SegmentedButton<ConverterEditorMode>(
                    key: const Key('editor-mode-selector'),
                    segments: const [
                      ButtonSegment(
                        value: ConverterEditorMode.grid,
                        icon: Icon(Icons.grid_on),
                        label: Text('智能表格'),
                      ),
                      ButtonSegment(
                        value: ConverterEditorMode.text,
                        icon: Icon(Icons.notes),
                        label: Text('文本输入'),
                      ),
                    ],
                    selected: {editorMode},
                    onSelectionChanged: (selection) =>
                        _switchEditorMode(selection.first),
                  ),
                ),
                const SizedBox(height: 12),
                if (editorMode == ConverterEditorMode.grid) ...[
                  const GlobalTableScaleControl(),
                  const SizedBox(height: 8),
                  SmartGridEditor(
                    key: _gridEditorKey,
                    document: gridDocument,
                    issues: result != null && _gridConversion != null
                        ? _gridConversion!.issues
                        : validateSmartGridDocument(gridDocument),
                    onChanged: _updateGrid,
                    onViewStateChanged: (document) => ref
                        .read(smartGridDocumentProvider.notifier)
                        .updateViewState(document),
                    panelSize: _panelSize('smart-grid'),
                    onPanelSizeChanged: (size) =>
                        _updatePanelSize('smart-grid', size),
                    scale: tableScale,
                  ),
                ] else ...[
                  ResizablePanel(
                    panelId: 'score-input',
                    size: _panelSize('score-input'),
                    onSizeChanged: (size) =>
                        _updatePanelSize('score-input', size),
                    initialHeight: _textInputDefaultHeight(context),
                    child: TextField(
                      key: const Key('score-input'),
                      controller: _scoreController,
                      focusNode: _scoreFocusNode,
                      inputFormatters: const [SemicolonLineBreakFormatter()],
                      expands: true,
                      maxLines: null,
                      keyboardType: TextInputType.multiline,
                      style: AppTypography.of(context).notationBody,
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
                  ),
                  const SizedBox(height: 12),
                  ResizablePanel(
                    panelId: 'lyrics-input',
                    size: _panelSize('lyrics-input'),
                    onSizeChanged: (size) =>
                        _updatePanelSize('lyrics-input', size),
                    initialHeight: _textInputDefaultHeight(context),
                    child: TextField(
                      key: const Key('lyrics-input'),
                      controller: _lyricsController,
                      inputFormatters: const [SemicolonLineBreakFormatter()],
                      expands: true,
                      maxLines: null,
                      keyboardType: TextInputType.multiline,
                      style: AppTypography.of(context).notationBody,
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
                  ),
                ],
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
                      onPressed: displayedResult == null ||
                              displayedResult.hasErrors ||
                              output.isEmpty
                          ? null
                          : _exportImage,
                      child: const Text('导出图片'),
                    ),
                    if (editorMode == ConverterEditorMode.grid)
                      FilledButton.tonal(
                        key: const Key('export-inspection-image-button'),
                        onPressed: result == null ||
                                _gridConversion == null ||
                                result.hasErrors
                            ? null
                            : _exportInspectionImage,
                        child: const Text('导出检查图'),
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
                if (editorMode == ConverterEditorMode.grid &&
                    _gridConversion != null) ...[
                  if (result == null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Row(children: [
                        Icon(Icons.update,
                            size: 18,
                            color: Theme.of(context).colorScheme.tertiary),
                        const SizedBox(width: 6),
                        Text(
                          '结果待更新',
                          style: Theme.of(context)
                              .textTheme
                              .labelLarge
                              ?.copyWith(
                                color: Theme.of(context).colorScheme.tertiary,
                              ),
                        ),
                      ]),
                    ),
                  Opacity(
                    opacity: result == null ? .55 : 1,
                    child: SmartGridOutputView(
                      document: _gridConversionDocument ?? gridDocument,
                      conversion: _gridConversion!,
                      onCellTap: (row, column) =>
                          _gridEditorKey.currentState?.focusCell(row, column),
                      panelSize: _panelSize('letter-grid'),
                      onPanelSizeChanged: (size) =>
                          _updatePanelSize('letter-grid', size),
                      scale: tableScale,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text('纯文本预览', style: Theme.of(context).textTheme.labelLarge),
                  const SizedBox(height: 6),
                ],
                ResizablePanel(
                  panelId: 'text-preview',
                  size: _panelSize('text-preview'),
                  onSizeChanged: (size) =>
                      _updatePanelSize('text-preview', size),
                  child: _isPreparingImageExport
                      ? OverflowBox(
                          alignment: Alignment.topLeft,
                          minWidth: 1200,
                          maxWidth: 1200,
                          child: _outputPanel(
                            imageOutput.isEmpty ? '转换结果将显示在这里' : imageOutput,
                            imageMode: true,
                            width: 1200,
                            songTitle: songTitle,
                          ),
                        )
                      : _outputPanel(
                          output.isEmpty ? '转换结果将显示在这里' : output,
                        ),
                ),
                if (displayedResult != null && displayedResult.hasErrors) ...[
                  const SizedBox(height: 12),
                  ...displayedResult.errors.map(
                    (error) => Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: Text(
                        error.message,
                        key: const Key('error-text'),
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                              color: Theme.of(context).colorScheme.error,
                            ),
                      ),
                    ),
                  ),
                  ...displayedResult.errors.map(
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
                if (displayedResult != null && displayedResult.hasWarnings) ...[
                  const SizedBox(height: 12),
                  ...displayedResult.warnings.map(
                    (warning) => Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: Text(
                        warning.message,
                        key: const Key('warning-text'),
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                              color: Theme.of(context).colorScheme.tertiary,
                            ),
                      ),
                    ),
                  ),
                ],
                if (displayedResult != null &&
                    displayedResult.unmatchedLyrics.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Text(
                    '未匹配歌词：${_formatUnmatchedLyrics(displayedResult.unmatchedLyricTokens)}',
                    key: const Key('unmatched-lyrics-text'),
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: Theme.of(context).colorScheme.tertiary,
                        ),
                  ),
                ],
                if (displayedResult != null &&
                    displayedResult.missingLyricNotePositions.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Text(
                    '缺少歌词的位置：${_formatMissingLyricNotes(displayedResult.missingLyricNotePositions)}',
                    key: const Key('missing-lyrics-position-text'),
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
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

class _SongDialog extends StatefulWidget {
  final SongRecord? source;
  final String title;
  final bool includeTitle;
  final String dialogTitle;
  final List<String> suggestions;

  const _SongDialog({
    required this.source,
    required this.title,
    required this.includeTitle,
    required this.dialogTitle,
    required this.suggestions,
  });

  @override
  State<_SongDialog> createState() => _SongDialogState();
}

class _SongDialogState extends State<_SongDialog> {
  late final TextEditingController _titleController;
  late final TextEditingController _artistController;
  late final TextEditingController _notesController;
  final _tagInputController = TextEditingController();
  late final List<String> _tags;

  @override
  void initState() {
    super.initState();
    _titleController = TextEditingController(text: widget.title);
    _artistController =
        TextEditingController(text: widget.source?.artist ?? '');
    _notesController = TextEditingController(text: widget.source?.notes ?? '');
    _tags = <String>[...?widget.source?.tags];
  }

  @override
  void dispose() {
    _titleController.dispose();
    _artistController.dispose();
    _notesController.dispose();
    _tagInputController.dispose();
    super.dispose();
  }

  void _addTag(String value) {
    final tag = value.trim();
    if (tag.isNotEmpty && !_tags.contains(tag)) {
      setState(() => _tags.add(tag));
    }
    _tagInputController.clear();
  }

  void _save() {
    final title = _titleController.text.trim();
    if (title.isEmpty) return;
    Navigator.pop(
      context,
      _SongFields(
        title,
        _artistController.text.trim(),
        List.unmodifiable(_tags),
        _notesController.text.trim(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: Text(widget.dialogTitle),
        content: SizedBox(
          width: 420,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (widget.includeTitle)
                  TextField(
                    controller: _titleController,
                    autofocus: true,
                    maxLength: 80,
                    decoration: const InputDecoration(labelText: '歌曲名 *'),
                  ),
                TextField(
                  controller: _artistController,
                  autofocus: !widget.includeTitle,
                  decoration: const InputDecoration(labelText: '歌手'),
                ),
                TextField(
                  controller: _tagInputController,
                  decoration: const InputDecoration(labelText: '标签（输入后按回车）'),
                  onSubmitted: _addTag,
                ),
                if (_tags.isNotEmpty)
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Wrap(
                      spacing: 4,
                      children: [
                        for (final tag in _tags)
                          InputChip(
                            label: Text(tag),
                            onDeleted: () => setState(() => _tags.remove(tag)),
                          ),
                      ],
                    ),
                  ),
                if (widget.suggestions.isNotEmpty)
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Wrap(
                      spacing: 4,
                      children: [
                        for (final tag in widget.suggestions
                            .where((tag) => !_tags.contains(tag)))
                          ActionChip(
                            label: Text(tag),
                            onPressed: () => setState(() => _tags.add(tag)),
                          ),
                      ],
                    ),
                  ),
                TextField(
                  controller: _notesController,
                  maxLines: 3,
                  decoration: const InputDecoration(labelText: '备注'),
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          FilledButton(
            key: const Key('song-dialog-save'),
            onPressed: _save,
            child: const Text('保存'),
          ),
        ],
      );
}

SongRecord? _songById(List<SongRecord> songs, String id) {
  for (final song in songs) {
    if (song.id == id) return song;
  }
  return null;
}

bool _sameSongGridContent(
  SmartGridDocument current,
  SmartGridDocument? saved,
) {
  if (current.isEmpty && (saved == null || saved.isEmpty)) return true;
  if (saved == null ||
      current.columnCount != saved.columnCount ||
      current.rows.length != saved.rows.length) {
    return false;
  }
  final currentGroups = _gridGroupPositions(current);
  final savedGroups = _gridGroupPositions(saved);
  for (var index = 0; index < current.rows.length; index++) {
    final currentRow = current.rows[index];
    final savedRow = saved.rows[index];
    if (currentRow.type != savedRow.type ||
        currentRow.cells.length != savedRow.cells.length ||
        currentGroups[index] != savedGroups[index]) {
      return false;
    }
    for (var column = 0; column < currentRow.cells.length; column++) {
      if (currentRow.cells[column] != savedRow.cells[column]) return false;
    }
  }
  return true;
}

List<int> _gridGroupPositions(SmartGridDocument document) {
  final firstRows = <String, int>{};
  return [
    for (var index = 0; index < document.rows.length; index++)
      firstRows.putIfAbsent(document.rows[index].groupId, () => index),
  ];
}

String _formatUnmatchedLyrics(List<LyricToken> tokens) => tokens
    .map((token) =>
        '${token.rawText}（第 ${token.line} 行第 ${token.elementIndex} 项）')
    .join(' ');

String _formatMissingLyricNotes(List<SourcePosition> positions) => positions
    .map((position) => '第 ${position.line} 行第 ${position.tokenIndex} 个元素')
    .join('、');
