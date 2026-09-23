import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/rendering.dart';

import '../../core/mapping/keyboard_mapping.dart';
import '../../core/mapping/mapping_draft.dart';
import '../converter/converter_providers.dart';
import '../converter/png_export_service.dart';
import 'song_library_file_service.dart';
import 'song_library_persistence.dart';
import 'song_library_providers.dart';
import 'song_record.dart';

class SongLoadRequest {
  final SongRecord song;
  const SongLoadRequest(this.song);
}

class SongLibraryPage extends ConsumerStatefulWidget {
  final String? currentSongId;
  const SongLibraryPage({super.key, this.currentSongId});
  @override
  ConsumerState<SongLibraryPage> createState() => _SongLibraryPageState();
}

class _SongLibraryPageState extends ConsumerState<SongLibraryPage> {
  String _query = '';
  String? _tag;
  var _sortByTitle = false;

  @override
  Widget build(BuildContext context) {
    final songs = ref.watch(songLibraryProvider);
    final tags = {for (final song in songs) ...song.tags}.toList()..sort();
    final filtered = songs.where((song) {
      final searchable =
          '${song.title} ${song.artist} ${song.notes} ${song.tags.join(' ')}'
              .toLowerCase();
      return (_query.isEmpty || searchable.contains(_query.toLowerCase())) &&
          (_tag == null || song.tags.contains(_tag));
    }).toList()
      ..sort((a, b) => _sortByTitle
          ? a.title.compareTo(b.title)
          : b.updatedAt.compareTo(a.updatedAt));
    return Scaffold(
      appBar: AppBar(title: const Text('曲谱库'), actions: [
        IconButton(
            tooltip: '导入备份',
            icon: const Icon(Icons.file_open),
            onPressed: _import),
        IconButton(
            tooltip: '导出全部',
            icon: const Icon(Icons.upload_file),
            onPressed: songs.isEmpty ? null : () => _export(songs)),
      ]),
      body: Column(children: [
        Padding(
            padding: const EdgeInsets.all(16),
            child: TextField(
              key: const Key('song-library-search'),
              decoration: const InputDecoration(
                  prefixIcon: Icon(Icons.search),
                  labelText: '搜索歌曲、歌手、标签或备注',
                  border: OutlineInputBorder()),
              onChanged: (value) => setState(() => _query = value.trim()),
            )),
        if (tags.isNotEmpty)
          SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(children: [
                ChoiceChip(
                    label: const Text('全部标签'),
                    selected: _tag == null,
                    onSelected: (_) => setState(() => _tag = null)),
                for (final tag in tags)
                  Padding(
                      padding: const EdgeInsets.only(left: 8),
                      child: ChoiceChip(
                          label: Text(tag),
                          selected: _tag == tag,
                          onSelected: (_) =>
                              setState(() => _tag = _tag == tag ? null : tag))),
              ])),
        Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
                onPressed: () => setState(() => _sortByTitle = !_sortByTitle),
                icon: const Icon(Icons.sort),
                label: Text(_sortByTitle ? '按歌曲名排序' : '按最近修改排序'))),
        Expanded(
            child: filtered.isEmpty
                ? const Center(child: Text('还没有保存曲谱。请在转换页选择“保存到曲谱库”。'))
                : ListView.builder(
                    itemCount: filtered.length,
                    itemBuilder: (context, index) {
                      final song = filtered[index];
                      return Card(
                          child: ListTile(
                        key: Key('song-card-${song.id}'),
                        selected: song.id == widget.currentSongId,
                        title: Text(song.title),
                        subtitle: Text([
                          if (song.artist.isNotEmpty) song.artist,
                          if (song.tags.isNotEmpty)
                            song.tags.map((tag) => '#$tag').join(' '),
                          song.result == null
                              ? '仅保存输入'
                              : song.resultIsStale
                                  ? '转换结果待更新'
                                  : '已保存转换结果'
                        ].join('  ·  ')),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () => Navigator.of(context)
                            .push(MaterialPageRoute<Object?>(
                                builder: (_) =>
                                    SongDetailPage(songId: song.id)))
                            .then((value) {
                          if (value is SongLoadRequest && mounted)
                            Navigator.pop(context, value);
                        }),
                      ));
                    }))
      ]),
    );
  }

  Future<void> _export(List<SongRecord> songs) async {
    try {
      final path = await const SongLibraryFileService()
          .saveJson(SongLibraryPersistence.encodeDocument(songs));
      if (mounted) _message(path == null ? '已取消导出' : '备份已导出');
    } catch (_) {
      if (mounted) _message('导出备份失败');
    }
  }

  Future<void> _import() async {
    try {
      final raw = await const SongLibraryFileService().openJson();
      if (raw == null) return;
      final incoming = SongLibraryPersistence.decodeDocument(raw);
      final current = ref.read(songLibraryProvider);
      final byId = {for (final item in current) item.id: item};
      final conflicts =
          incoming.where((item) => byId.containsKey(item.id)).toList();
      var overwrite = false;
      if (conflicts.isNotEmpty && mounted) {
        final decision = await showDialog<bool>(
            context: context,
            builder: (context) => AlertDialog(
                    title: Text('发现 ${conflicts.length} 条同名记录'),
                    content: const Text('覆盖会用备份中的同一条记录替换本机记录。'),
                    actions: [
                      TextButton(
                          onPressed: () => Navigator.pop(context, null),
                          child: const Text('取消')),
                      TextButton(
                          onPressed: () => Navigator.pop(context, false),
                          child: const Text('保留本机')),
                      FilledButton(
                          onPressed: () => Navigator.pop(context, true),
                          child: const Text('全部覆盖'))
                    ]));
        if (decision == null) return;
        overwrite = decision;
      }
      final next = [...current];
      for (final song in incoming) {
        final index = next.indexWhere((item) => item.id == song.id);
        if (index < 0)
          next.add(song);
        else if (overwrite) next[index] = song;
      }
      await ref.read(songLibraryProvider.notifier).replaceAll(next);
      if (mounted) _message('已导入 ${incoming.length} 条曲谱');
    } on FormatException {
      if (mounted) _message('备份文件格式无效，未导入任何内容');
    } catch (_) {
      if (mounted) _message('导入备份失败');
    }
  }

  void _message(String value) => ScaffoldMessenger.of(context)
      .showSnackBar(SnackBar(content: Text(value)));
}

class SongDetailPage extends ConsumerWidget {
  final String songId;
  final GlobalKey _snapshotImageKey = GlobalKey();
  SongDetailPage({super.key, required this.songId});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    SongRecord? song;
    for (final item in ref.watch(songLibraryProvider)) {
      if (item.id == songId) {
        song = item;
        break;
      }
    }
    if (song == null)
      return const Scaffold(body: Center(child: Text('该曲谱已删除')));
    final selectedSong = song;
    return Scaffold(
        appBar: AppBar(title: Text(selectedSong.title), actions: [
          IconButton(
              tooltip: '导出此曲',
              icon: const Icon(Icons.upload_file),
              onPressed: () async {
                final path = await const SongLibraryFileService().saveJson(
                    SongLibraryPersistence.encodeDocument([selectedSong]),
                    suggestedName: '${selectedSong.title}.json');
                if (context.mounted)
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                      content: Text(path == null ? '已取消导出' : '曲谱已导出')));
              })
        ]),
        body: ListView(padding: const EdgeInsets.all(16), children: [
          if (selectedSong.artist.isNotEmpty)
            Text(selectedSong.artist,
                style: Theme.of(context).textTheme.titleMedium),
          if (selectedSong.tags.isNotEmpty)
            Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Wrap(
                    spacing: 6,
                    children: selectedSong.tags
                        .map((tag) => Chip(label: Text(tag)))
                        .toList())),
          if (selectedSong.notes.isNotEmpty)
            Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(selectedSong.notes)),
          const SizedBox(height: 16),
          FilledButton.icon(
              onPressed: () =>
                  Navigator.of(context).pop(SongLoadRequest(selectedSong)),
              icon: const Icon(Icons.input),
              label: const Text('一键填入转换页')),
          if (selectedSong.result != null) ...[
            const SizedBox(height: 12),
            Text(selectedSong.resultIsStale ? '上次保存的字母简谱（待更新）' : '已保存的字母简谱',
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            RepaintBoundary(
                key: _snapshotImageKey,
                child: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                        border: Border.all(
                            color:
                                Theme.of(context).colorScheme.outlineVariant),
                        borderRadius: BorderRadius.circular(8)),
                    child: SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: SelectableText(selectedSong.result!.output,
                            style: const TextStyle(
                                fontFamily: 'NSimSun',
                                fontFamilyFallback: [
                                  'SimSun',
                                  'Consolas',
                                  'monospace'
                                ],
                                height: 1.5))))),
            Wrap(spacing: 8, children: [
              TextButton.icon(
                  onPressed: () async {
                    await Clipboard.setData(
                        ClipboardData(text: selectedSong.result!.output));
                    if (context.mounted)
                      ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('已复制转换结果')));
                  },
                  icon: const Icon(Icons.copy),
                  label: const Text('复制')),
              TextButton.icon(
                  onPressed: () => _exportSnapshot(context),
                  icon: const Icon(Icons.image),
                  label: const Text('导出图片')),
              TextButton.icon(
                  onPressed: () => _applyMapping(context, ref, selectedSong),
                  icon: const Icon(Icons.keyboard),
                  label: const Text('应用保存的键位'))
            ]),
          ],
          const SizedBox(height: 24),
          OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                  foregroundColor: Theme.of(context).colorScheme.error),
              onPressed: () => _delete(context, ref, selectedSong),
              icon: const Icon(Icons.delete),
              label: const Text('删除曲谱')),
        ]));
  }

  Future<void> _applyMapping(
      BuildContext context, WidgetRef ref, SongRecord song) async {
    final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
                title: const Text('应用保存的键位？'),
                content: const Text('会替换当前键盘映射，并清除当前转换结果。'),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(context, false),
                      child: const Text('取消')),
                  FilledButton(
                      onPressed: () => Navigator.pop(context, true),
                      child: const Text('应用'))
                ]));
    if (confirmed != true) return;
    final parsed = KeyboardMapping.fromJson(song.result!.mapping);
    if (!parsed.isValid) return;
    ref
        .read(mappingDraftProvider.notifier)
        .updateMapping(MappingDraft.fromMapping(parsed.mapping!));
    if (context.mounted)
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('已应用保存的键位')));
  }

  Future<void> _exportSnapshot(BuildContext context) async {
    try {
      final boundary = _snapshotImageKey.currentContext?.findRenderObject()
          as RenderRepaintBoundary?;
      if (boundary == null) throw StateError('缺少可导出的内容');
      final image = await boundary.toImage(pixelRatio: 3);
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      image.dispose();
      if (data == null) throw StateError('无法生成图片');
      final path = await const PngExportService().export(
        Uint8List.view(data.buffer),
      );
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(path == null ? '已取消导出' : '图片已保存')),
        );
      }
    } on Object {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('导出图片失败，请重试。')));
      }
    }
  }

  Future<void> _delete(
      BuildContext context, WidgetRef ref, SongRecord song) async {
    final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
                title: const Text('删除曲谱？'),
                content: Text('“${song.title}”将从曲谱库删除。'),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(context, false),
                      child: const Text('取消')),
                  FilledButton(
                      onPressed: () => Navigator.pop(context, true),
                      child: const Text('删除'))
                ]));
    if (confirmed != true) return;
    await ref.read(songLibraryProvider.notifier).delete(song.id);
    if (context.mounted) {
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: const Text('已删除曲谱'),
          action: SnackBarAction(
              label: '撤销',
              onPressed: () =>
                  ref.read(songLibraryProvider.notifier).saveRecord(song))));
    }
  }
}
