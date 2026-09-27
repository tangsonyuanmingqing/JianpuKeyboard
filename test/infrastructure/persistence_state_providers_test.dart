import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jianpu_keyboard/features/converter/converter_providers.dart';
import 'package:jianpu_keyboard/features/library/song_library_providers.dart';
import 'package:jianpu_keyboard/infrastructure/persistence_load_result.dart';
import 'package:jianpu_keyboard/infrastructure/storage_health.dart';

void main() {
  test('draft and library health transitions remain isolated', () {
    const damagedDraft = StorageHealth(
      status: PersistenceLoadStatus.corrupt,
      message: '草稿损坏',
      rawData: '{broken',
    );
    const damagedLibrary = StorageHealth(
      status: PersistenceLoadStatus.migrationFailed,
      message: '曲谱库迁移失败',
      rawData: '{legacy',
    );
    final container = ProviderContainer(overrides: [
      initialDraftStorageHealthProvider.overrideWithValue(damagedDraft),
      initialSongLibraryStorageHealthProvider.overrideWithValue(damagedLibrary),
    ]);
    addTearDown(container.dispose);

    container.read(draftStorageHealthProvider.notifier).markRawDataExported();
    expect(container.read(draftStorageHealthProvider).rawDataExported, true);
    expect(container.read(songLibraryStorageHealthProvider).rawDataExported,
        false);

    container.read(draftStorageHealthProvider.notifier).markHealthy();
    expect(
      container.read(draftStorageHealthProvider).status,
      PersistenceLoadStatus.normal,
    );
    expect(container.read(draftStorageHealthProvider).rawData, isNull);
    expect(
      container.read(songLibraryStorageHealthProvider).status,
      PersistenceLoadStatus.migrationFailed,
    );
    expect(container.read(songLibraryStorageHealthProvider).rawData, '{legacy');

    container
        .read(songLibraryStorageHealthProvider.notifier)
        .markRawDataExported();
    expect(
        container.read(songLibraryStorageHealthProvider).rawDataExported, true);
    expect(container.read(draftStorageHealthProvider).rawDataExported, false);

    container.read(songLibraryStorageHealthProvider.notifier).markHealthy();
    expect(
      container.read(songLibraryStorageHealthProvider).status,
      PersistenceLoadStatus.normal,
    );
    expect(container.read(songLibraryStorageHealthProvider).rawData, isNull);
    expect(
      container.read(draftStorageHealthProvider).status,
      PersistenceLoadStatus.normal,
    );
  });

  test('draft and library write-state transitions remain isolated', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    container.read(draftWriteStateProvider.notifier).saving();
    expect(
      container.read(draftWriteStateProvider).phase,
      PersistenceWritePhase.saving,
    );
    expect(
      container.read(songLibraryWriteStateProvider).phase,
      PersistenceWritePhase.idle,
    );

    container.read(draftWriteStateProvider.notifier).failed('草稿保存失败');
    container.read(songLibraryWriteStateProvider.notifier).saved();
    expect(
      container.read(draftWriteStateProvider),
      isA<PersistenceWriteState>()
          .having((state) => state.phase, 'phase', PersistenceWritePhase.failed)
          .having((state) => state.message, 'message', '草稿保存失败'),
    );
    expect(
      container.read(songLibraryWriteStateProvider).phase,
      PersistenceWritePhase.saved,
    );
    container.read(draftWriteStateProvider.notifier).saving();
    expect(container.read(draftWriteStateProvider).message, isNull);
    container.read(draftWriteStateProvider.notifier).saved();
    expect(container.read(draftWriteStateProvider).message, isNull);
    container.read(songLibraryWriteStateProvider.notifier).failed('库失败');
    expect(container.read(draftWriteStateProvider).phase,
        PersistenceWritePhase.saved);
    expect(container.read(songLibraryWriteStateProvider).message, '库失败');
  });
}
