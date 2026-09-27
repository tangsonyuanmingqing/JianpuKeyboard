import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jianpu_keyboard/features/converter/converter_input.dart';
import 'package:jianpu_keyboard/features/library/song_library_persistence.dart';
import 'package:jianpu_keyboard/features/library/song_library_providers.dart';
import 'package:jianpu_keyboard/features/library/song_record.dart';
import 'package:jianpu_keyboard/infrastructure/recovery_providers.dart';
import 'package:jianpu_keyboard/infrastructure/recovery_snapshot_repository.dart';
import 'package:jianpu_keyboard/infrastructure/storage_health.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  final original = SongRecord(
    id: 'song-1',
    title: '原曲',
    input: const ConverterInput(scoreText: '3', lyricsText: '晨'),
    createdAt: DateTime.utc(2026, 9, 25),
    updatedAt: DateTime.utc(2026, 9, 25),
  );

  test('publishes a library mutation only after persistence succeeds',
      () async {
    final persistence = _ControlledPersistence();
    final snapshots = _SnapshotFake();
    final container = ProviderContainer(overrides: [
      initialSongLibraryProvider.overrideWithValue([original]),
      songLibraryPersistenceProvider.overrideWithValue(persistence),
      recoverySnapshotRepositoryProvider.overrideWithValue(snapshots),
    ]);
    addTearDown(container.dispose);
    final changed = original.copyWith(title: '新标题');

    final write =
        container.read(songLibraryProvider.notifier).saveRecord(changed);
    await Future<void>.delayed(Duration.zero);

    expect(container.read(songLibraryProvider).single.title, '原曲');
    expect(snapshots.created, 1);
    expect(
      container.read(songLibraryWriteStateProvider).phase,
      PersistenceWritePhase.saving,
    );

    persistence.complete();
    await write;
    expect(container.read(songLibraryProvider).single.title, '新标题');
    expect(
      container.read(songLibraryWriteStateProvider).phase,
      PersistenceWritePhase.saved,
    );
  });

  test('keeps the previous library when persistence fails', () async {
    final persistence = _ControlledPersistence();
    final container = ProviderContainer(overrides: [
      initialSongLibraryProvider.overrideWithValue([original]),
      songLibraryPersistenceProvider.overrideWithValue(persistence),
      recoverySnapshotRepositoryProvider.overrideWithValue(_SnapshotFake()),
    ]);
    addTearDown(container.dispose);

    final write =
        container.read(songLibraryProvider.notifier).delete(original.id);
    await Future<void>.delayed(Duration.zero);
    persistence.fail();

    await expectLater(write, throwsStateError);
    expect(container.read(songLibraryProvider), [original]);
    expect(
      container.read(songLibraryWriteStateProvider).phase,
      PersistenceWritePhase.failed,
    );
  });

  test('serializes complete library transactions without losing updates',
      () async {
    final persistence = _QueueingPersistence();
    final container = ProviderContainer(overrides: [
      initialSongLibraryProvider.overrideWithValue([original]),
      songLibraryPersistenceProvider.overrideWithValue(persistence),
      recoverySnapshotRepositoryProvider.overrideWithValue(_SnapshotFake()),
    ]);
    addTearDown(container.dispose);
    final changed = original.copyWith(title: '新标题');
    final added = SongRecord(
      id: 'song-2',
      title: '第二首',
      input: const ConverterInput(scoreText: '4'),
      createdAt: DateTime.utc(2026, 9, 26),
      updatedAt: DateTime.utc(2026, 9, 26),
    );

    final first =
        container.read(songLibraryProvider.notifier).saveRecord(changed);
    final second =
        container.read(songLibraryProvider.notifier).saveRecord(added);
    await Future<void>.delayed(Duration.zero);

    expect(persistence.saved, hasLength(1));
    persistence.complete(0);
    await Future<void>.delayed(Duration.zero);
    expect(persistence.saved, hasLength(2));
    expect(persistence.saved.last.map((song) => song.id), ['song-1', 'song-2']);

    persistence.complete(1);
    await Future.wait([first, second]);
    expect(container.read(songLibraryProvider), [changed, added]);
  });
}

class _ControlledPersistence extends SongLibraryPersistence {
  _ControlledPersistence() : super(preferences: _PreferencesFake());

  Completer<void>? _pending;

  @override
  Future<void> save(List<SongRecord> songs) {
    _pending = Completer<void>();
    return _pending!.future;
  }

  void complete() => _pending!.complete();
  void fail() => _pending!.completeError(StateError('write failed'));
}

class _SnapshotFake extends RecoverySnapshotRepository {
  var created = 0;

  @override
  Future<RecoverySnapshot?> create({
    required RecoverySnapshotType type,
    required Object? payload,
    required RecoverySnapshotSource source,
    String? note,
    bool deduplicate = false,
  }) async {
    created++;
    return null;
  }
}

class _QueueingPersistence extends SongLibraryPersistence {
  _QueueingPersistence() : super(preferences: _PreferencesFake());

  final List<List<SongRecord>> saved = [];
  final List<Completer<void>> pending = [];

  @override
  Future<void> save(List<SongRecord> songs) {
    saved.add(List.of(songs));
    final completer = Completer<void>();
    pending.add(completer);
    return completer.future;
  }

  void complete(int index) => pending[index].complete();
}

class _PreferencesFake extends Fake implements SharedPreferencesAsync {}
