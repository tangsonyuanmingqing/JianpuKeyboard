import 'dart:convert';
import 'dart:math';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../infrastructure/persistence_load_result.dart';
import '../../infrastructure/app_data_store.dart';
import '../../infrastructure/recovery_providers.dart';
import '../../infrastructure/recovery_snapshot_repository.dart';
import '../../infrastructure/storage_health.dart';
import '../../infrastructure/persistence_state_notifiers.dart';
import 'song_library_persistence.dart';
import 'song_record.dart';

class SongLibraryNotifier extends Notifier<List<SongRecord>> {
  final SerialOperationQueue _transactions = SerialOperationQueue();

  @override
  List<SongRecord> build() => ref.read(initialSongLibraryProvider);

  Future<void> saveRecord(SongRecord record) => _transactions.run(() async {
        final index = state.indexWhere((item) => item.id == record.id);
        final next = [...state];
        if (index == -1) {
          next.add(record);
        } else {
          next[index] = record;
        }
        await _replaceTransactionally(next);
      });

  Future<void> delete(String id) => _transactions.run(
        () => _replaceTransactionally(
          state.where((song) => song.id != id).toList(),
        ),
      );

  Future<void> replaceAll(List<SongRecord> songs) =>
      _transactions.run(() => _replaceTransactionally(songs));

  Future<void> restoreSnapshot(List<SongRecord> songs) =>
      _transactions.run(() async {
        final snapshots = ref.read(recoverySnapshotRepositoryProvider);
        await snapshots.create(
          type: RecoverySnapshotType.library,
          payload: jsonDecode(SongLibraryPersistence.encodeDocument(state)),
          source: RecoverySnapshotSource.beforeRestore,
          deduplicate: true,
        );
        await _persistThenPublish(songs);
      });

  Future<void> resetAfterCorruption() => _transactions.run(() async {
        final health = ref.read(songLibraryStorageHealthProvider);
        if (health.rawData != null && !health.rawDataExported) {
          throw StateError('必须先导出损坏的原始曲谱库数据。');
        }
        await ref.read(songLibraryPersistenceProvider).reset();
        state = const [];
        ref.read(songLibraryStorageHealthProvider.notifier).markHealthy();
      });

  Future<void> _replaceTransactionally(List<SongRecord> songs) async {
    _ensureWritable();
    await ref.read(recoverySnapshotRepositoryProvider).create(
          type: RecoverySnapshotType.library,
          payload: jsonDecode(SongLibraryPersistence.encodeDocument(state)),
          source: RecoverySnapshotSource.automatic,
          deduplicate: true,
        );
    await _persistThenPublish(songs);
  }

  Future<void> _persistThenPublish(List<SongRecord> songs) async {
    final previous = state;
    ref.read(songLibraryWriteStateProvider.notifier).saving();
    try {
      await ref.read(songLibraryPersistenceProvider).save(songs);
      state = List.unmodifiable(songs);
      ref.read(songLibraryWriteStateProvider.notifier).saved();
    } on Object {
      state = previous;
      ref.read(songLibraryWriteStateProvider.notifier).failed('曲谱库保存失败，请重试。');
      rethrow;
    }
  }

  void _ensureWritable() {
    if (ref.read(songLibraryStorageHealthProvider).blocksWrites) {
      throw StateError('曲谱库需要先恢复或重置。');
    }
  }
}

class SongLibraryStorageHealthNotifier extends StorageHealthNotifier {
  @override
  StorageHealth build() => ref.read(initialSongLibraryStorageHealthProvider);
}

class SongLibraryWriteStateNotifier extends PersistenceWriteStateNotifier {}

final songLibraryPersistenceProvider = Provider<SongLibraryPersistence>(
  (ref) => SongLibraryPersistence(),
);

final initialSongLibraryProvider =
    Provider<List<SongRecord>>((ref) => const []);

final initialSongLibraryStorageHealthProvider = Provider<StorageHealth>(
  (ref) => const StorageHealth(status: PersistenceLoadStatus.missing),
);

final songLibraryStorageHealthProvider =
    NotifierProvider<SongLibraryStorageHealthNotifier, StorageHealth>(
  SongLibraryStorageHealthNotifier.new,
);

final songLibraryWriteStateProvider =
    NotifierProvider<SongLibraryWriteStateNotifier, PersistenceWriteState>(
  SongLibraryWriteStateNotifier.new,
);

final songLibraryProvider =
    NotifierProvider<SongLibraryNotifier, List<SongRecord>>(
  SongLibraryNotifier.new,
);

String newSongId() =>
    '${DateTime.now().microsecondsSinceEpoch.toRadixString(36)}'
    '${Random.secure().nextInt(1 << 32).toRadixString(36)}';
