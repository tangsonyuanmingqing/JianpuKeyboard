import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app/app.dart';
import 'features/converter/converter_draft_persistence.dart';
import 'features/converter/converter_providers.dart';
import 'features/converter/mapping_persistence.dart';
import 'features/converter/smart_grid_document.dart';
import 'features/library/song_library_persistence.dart';
import 'features/library/song_library_providers.dart';
import 'features/library/song_record.dart';
import 'infrastructure/shared_preferences_mapping_storage.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final persistence = MappingPersistence(SharedPreferencesMappingStorage());
  final loadedMapping = await persistence.load();
  final draftPersistence = ConverterDraftPersistence();
  final loadedDraft = await draftPersistence.load();
  final songLibraryPersistence = SongLibraryPersistence();
  List<SongRecord> loadedSongs;
  try {
    loadedSongs = await songLibraryPersistence.load();
  } on Object {
    loadedSongs = const [];
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
        initialConverterInputProvider.overrideWithValue(loadedDraft.input),
        initialDraftPersistenceMessageProvider.overrideWithValue(
          loadedDraft.message,
        ),
        initialDraftRestoredProvider.overrideWithValue(loadedDraft.wasRestored),
        songLibraryPersistenceProvider
            .overrideWithValue(songLibraryPersistence),
        initialSongLibraryProvider.overrideWithValue(loadedSongs),
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
