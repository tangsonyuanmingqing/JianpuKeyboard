import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app/app.dart';
import 'app/theme/app_theme_mode.dart';
import 'features/converter/converter_draft_persistence.dart';
import 'features/converter/converter_input.dart';
import 'features/converter/converter_providers.dart';
import 'features/converter/mapping_persistence.dart';
import 'features/converter/smart_grid_document.dart';
import 'features/converter/table_scale.dart';
import 'features/library/song_library_persistence.dart';
import 'features/library/song_library_providers.dart';
import 'features/library/song_record.dart';
import 'infrastructure/app_data_store.dart';
import 'infrastructure/persistence_load_result.dart';
import 'infrastructure/recovery_providers.dart';
import 'infrastructure/recovery_snapshot_repository.dart';
import 'infrastructure/shared_preferences_mapping_storage.dart';
import 'infrastructure/storage_health.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final persistence = MappingPersistence(SharedPreferencesMappingStorage());
  final loadedMapping = await persistence.load();
  final fileStore = AtomicFileStore();
  final recoverySnapshots = RecoverySnapshotRepository(store: fileStore);
  final draftPersistence = ConverterDraftPersistence(store: fileStore);
  ConverterDraftLoadResult loadedDraft;
  try {
    loadedDraft = await draftPersistence.load();
  } on Object {
    loadedDraft = const ConverterDraftLoadResult(
      ConverterInput(),
      status: PersistenceLoadStatus.migrationFailed,
      message: '无法访问草稿存储位置，修复前不会覆盖草稿。',
    );
  }
  final tableScalePersistence = TableScalePersistence();
  final loadedTableScale = await tableScalePersistence.load();
  final themePreferencePersistence = ThemePreferencePersistence();
  final loadedThemeMode = await themePreferencePersistence.load();
  final songLibraryPersistence = SongLibraryPersistence(store: fileStore);
  PersistenceLoadResult<List<SongRecord>> loadedLibrary;
  try {
    loadedLibrary = await songLibraryPersistence.loadDetailed();
  } on Object {
    loadedLibrary = const PersistenceLoadResult(
      value: [],
      status: PersistenceLoadStatus.migrationFailed,
      message: '无法访问曲谱库存储位置，修复前不会覆盖曲谱库。',
    );
  }
  runApp(
    ProviderScope(
      overrides: [
        mappingPersistenceProvider.overrideWithValue(persistence),
        initialMappingDraftProvider.overrideWithValue(loadedMapping.draft),
        initialMappingPersistenceMessageProvider.overrideWithValue(
          loadedMapping.message,
        ),
        converterDraftPersistenceProvider.overrideWithValue(draftPersistence),
        recoverySnapshotRepositoryProvider.overrideWithValue(recoverySnapshots),
        initialConverterInputProvider.overrideWithValue(loadedDraft.input),
        initialSongTitleProvider.overrideWithValue(loadedDraft.songTitle),
        initialDraftPersistenceMessageProvider.overrideWithValue(
          loadedDraft.message,
        ),
        initialDraftStorageHealthProvider.overrideWithValue(
          StorageHealth(
            status: loadedDraft.status,
            message: loadedDraft.message,
            rawData: loadedDraft.rawData,
          ),
        ),
        initialDraftRestoredProvider.overrideWithValue(loadedDraft.wasRestored),
        tableScalePersistenceProvider.overrideWithValue(tableScalePersistence),
        initialTableScaleProvider.overrideWithValue(loadedTableScale),
        themePreferencePersistenceProvider
            .overrideWithValue(themePreferencePersistence),
        initialThemeModeProvider.overrideWithValue(loadedThemeMode),
        songLibraryPersistenceProvider
            .overrideWithValue(songLibraryPersistence),
        initialSongLibraryProvider.overrideWithValue(loadedLibrary.value),
        initialSongLibraryStorageHealthProvider.overrideWithValue(
          StorageHealth(
            status: loadedLibrary.status,
            message: loadedLibrary.message,
            rawData: loadedLibrary.rawData,
          ),
        ),
        initialCurrentSongIdProvider.overrideWithValue(loadedDraft.songId),
        initialSmartGridDocumentProvider.overrideWithValue(
          loadedDraft.gridDocument ?? SmartGridDocument.empty(),
        ),
        initialEditorModeProvider.overrideWithValue(
          loadedDraft.editorMode == 'text' && loadedDraft.wasRestored
              ? ConverterEditorMode.text
              : ConverterEditorMode.grid,
        ),
      ],
      child: const JianpuKeyboardApp(),
    ),
  );
}
