import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme/app_theme_mode.dart';
import '../../app/window/window_pin.dart';
import '../../infrastructure/recovery_providers.dart';
import '../../infrastructure/recovery_snapshot_repository.dart';
import '../../infrastructure/storage_health.dart';
import '../converter/converter_draft_persistence.dart';
import '../converter/converter_input.dart';
import '../converter/converter_providers.dart';
import 'song_library_file_service.dart';
import 'song_library_persistence.dart';
import 'song_library_providers.dart';

class DraftRecoveryRequest {
  const DraftRecoveryRequest(this.draft);

  final ConverterDraftLoadResult draft;
}

class RecoveryCenterPage extends ConsumerStatefulWidget {
  const RecoveryCenterPage({super.key});

  @override
  ConsumerState<RecoveryCenterPage> createState() => _RecoveryCenterPageState();
}

class _RecoveryCenterPageState extends ConsumerState<RecoveryCenterPage>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs;
  var _refresh = 0;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('备份与恢复'),
        bottom: TabBar(
          controller: _tabs,
          tabs: const [Tab(text: '曲谱库'), Tab(text: '当前草稿')],
        ),
        actions: const [ThemeToggleButton(), WindowPinToggleButton()],
      ),
      body: TabBarView(
        controller: _tabs,
        children: [
          _snapshotView(RecoverySnapshotType.library, _refresh),
          _snapshotView(RecoverySnapshotType.draft, _refresh),
        ],
      ),
    );
  }

  Widget _snapshotView(RecoverySnapshotType type, int refresh) {
    final health = type == RecoverySnapshotType.library
        ? ref.watch(songLibraryStorageHealthProvider)
        : ref.watch(draftStorageHealthProvider);
    return FutureBuilder<List<RecoverySnapshot>>(
      key: ValueKey('${type.name}-$refresh'),
      future: ref.read(recoverySnapshotRepositoryProvider).list(type),
      builder: (context, snapshot) {
        final items = snapshot.data ?? const <RecoverySnapshot>[];
        return Column(
          children: [
            if (health.blocksWrites) _damagedDataBanner(type, health),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  FilledButton.icon(
                    onPressed: health.blocksWrites
                        ? null
                        : () => _createManualSnapshot(type),
                    icon: const Icon(Icons.add),
                    label: const Text('创建快照'),
                  ),
                  const SizedBox(width: 12),
                  Text('保留最近 20 份，共 ${items.length} 份'),
                ],
              ),
            ),
            Expanded(
              child: snapshot.connectionState != ConnectionState.done
                  ? const Center(child: CircularProgressIndicator())
                  : items.isEmpty
                      ? const Center(child: Text('还没有可用快照'))
                      : ListView.builder(
                          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                          itemCount: items.length,
                          itemBuilder: (context, index) =>
                              _snapshotCard(items[index]),
                        ),
            ),
          ],
        );
      },
    );
  }

  Widget _damagedDataBanner(
    RecoverySnapshotType type,
    StorageHealth health,
  ) {
    return MaterialBanner(
      content: Text(health.message ?? '当前数据需要恢复。'),
      actions: [
        TextButton(
          onPressed: health.rawData == null
              ? null
              : () => _exportDamagedData(type, health.rawData!),
          child: const Text('导出原始数据'),
        ),
        TextButton(
          onPressed: health.rawData != null && !health.rawDataExported
              ? null
              : () => _resetDamagedData(type),
          child: const Text('重置为空'),
        ),
      ],
    );
  }

  Widget _snapshotCard(RecoverySnapshot snapshot) {
    final sourceLabel = switch (snapshot.source) {
      RecoverySnapshotSource.automatic => '自动备份',
      RecoverySnapshotSource.manual => '手动快照',
      RecoverySnapshotSource.beforeRestore => '恢复前备份',
    };
    return Card(
      child: ListTile(
        title: Text(
            snapshot.note?.isNotEmpty == true ? snapshot.note! : sourceLabel),
        subtitle: Text('$sourceLabel · ${_formatTime(snapshot.createdAt)}'),
        trailing: Wrap(
          spacing: 4,
          children: [
            IconButton(
              tooltip: '预览',
              onPressed: () => _preview(snapshot),
              icon: const Icon(Icons.visibility_outlined),
            ),
            IconButton(
              tooltip: '导出',
              onPressed: () => _exportSnapshot(snapshot),
              icon: const Icon(Icons.download_outlined),
            ),
            IconButton(
              tooltip: '恢复',
              onPressed: () => _restore(snapshot),
              icon: const Icon(Icons.restore),
            ),
            IconButton(
              tooltip: '删除',
              onPressed: () => _delete(snapshot),
              icon: const Icon(Icons.delete_outline),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _createManualSnapshot(RecoverySnapshotType type) async {
    var note = '';
    final accepted = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('创建手动快照'),
        content: TextField(
          onChanged: (value) => note = value,
          maxLength: 80,
          decoration: const InputDecoration(
            labelText: '备注（可选）',
            hintText: '例如：修改副歌前',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('创建'),
          ),
        ],
      ),
    );
    if (accepted != true) return;
    final payload = type == RecoverySnapshotType.library
        ? jsonDecode(SongLibraryPersistence.encodeDocument(
            ref.read(songLibraryProvider),
          ))
        : jsonDecode(_currentDraftRaw());
    await ref.read(recoverySnapshotRepositoryProvider).create(
          type: type,
          payload: payload,
          source: RecoverySnapshotSource.manual,
          note: note,
        );
    _reload('快照已创建');
  }

  Future<void> _preview(RecoverySnapshot snapshot) async {
    final pretty = const JsonEncoder.withIndent('  ').convert(snapshot.payload);
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('快照预览'),
        content: SizedBox(
          width: 720,
          child: SingleChildScrollView(child: SelectableText(pretty)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('关闭'),
          ),
        ],
      ),
    );
  }

  Future<void> _exportSnapshot(RecoverySnapshot snapshot) async {
    final name = 'jianpu-${snapshot.type.name}-${snapshot.id}.json';
    final path = await const SongLibraryFileService().saveJson(
      jsonEncode(snapshot.toJson()),
      suggestedName: name,
    );
    if (mounted) _message(path == null ? '已取消导出' : '快照已导出');
  }

  Future<void> _restore(RecoverySnapshot snapshot) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('恢复此快照？'),
        content: const Text('恢复前会自动备份当前内容。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('恢复'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      if (snapshot.type == RecoverySnapshotType.library) {
        final songs = SongLibraryPersistence.decodeDocument(
          jsonEncode(snapshot.payload),
        );
        await ref.read(songLibraryProvider.notifier).restoreSnapshot(songs);
        ref.read(songLibraryStorageHealthProvider.notifier).markHealthy();
        _reload('曲谱库已恢复');
        return;
      }
      await ref.read(recoverySnapshotRepositoryProvider).create(
            type: RecoverySnapshotType.draft,
            payload: jsonDecode(_currentDraftRaw()),
            source: RecoverySnapshotSource.beforeRestore,
            deduplicate: true,
          );
      final raw = jsonEncode(snapshot.payload);
      final restored = ConverterDraftPersistence.decodeDocument(raw);
      await ref.read(converterDraftPersistenceProvider).restoreRaw(raw);
      ref.read(draftStorageHealthProvider.notifier).markHealthy();
      if (mounted) Navigator.pop(context, DraftRecoveryRequest(restored));
    } on Object {
      if (mounted) _message('快照恢复失败，当前数据未更改');
    }
  }

  Future<void> _delete(RecoverySnapshot snapshot) async {
    await ref.read(recoverySnapshotRepositoryProvider).delete(snapshot);
    _reload('快照已删除');
  }

  Future<void> _exportDamagedData(
    RecoverySnapshotType type,
    String raw,
  ) async {
    final path = await const SongLibraryFileService().saveJson(
      raw,
      suggestedName: 'jianpu-damaged-${type.name}.json',
    );
    if (path == null || !mounted) return;
    if (type == RecoverySnapshotType.library) {
      ref.read(songLibraryStorageHealthProvider.notifier).markRawDataExported();
    } else {
      ref.read(draftStorageHealthProvider.notifier).markRawDataExported();
    }
    _message('原始数据已导出，现在可以重置');
  }

  Future<void> _resetDamagedData(RecoverySnapshotType type) async {
    try {
      if (type == RecoverySnapshotType.library) {
        await ref.read(songLibraryProvider.notifier).resetAfterCorruption();
        _reload('曲谱库已重置');
      } else {
        final health = ref.read(draftStorageHealthProvider);
        if (health.rawData != null && !health.rawDataExported) {
          throw StateError('请先导出原始数据');
        }
        await ref.read(converterDraftPersistenceProvider).clear();
        ref.read(draftStorageHealthProvider.notifier).markHealthy();
        if (mounted) {
          Navigator.pop(
            context,
            const DraftRecoveryRequest(
              ConverterDraftLoadResult(ConverterInput()),
            ),
          );
        }
      }
    } on Object {
      if (mounted) _message('重置失败，请重试');
    }
  }

  String _currentDraftRaw() => ConverterDraftPersistence.encodeDocument(
        ref.read(converterInputProvider),
        songTitle: ref.read(songTitleProvider),
        songId: ref.read(currentSongIdProvider),
        gridDocument: ref.read(smartGridDocumentProvider),
        editorMode: ref.read(editorModeProvider).name,
      );

  void _reload(String message) {
    if (!mounted) return;
    setState(() => _refresh++);
    _message(message);
  }

  void _message(String message) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  String _formatTime(DateTime value) {
    final local = value.toLocal();
    String two(int number) => number.toString().padLeft(2, '0');
    return '${local.year}-${two(local.month)}-${two(local.day)} '
        '${two(local.hour)}:${two(local.minute)}:${two(local.second)}';
  }
}
