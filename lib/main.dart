import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app/app.dart';
import 'features/converter/converter_draft_persistence.dart';
import 'features/converter/converter_providers.dart';
import 'features/converter/mapping_persistence.dart';
import 'infrastructure/shared_preferences_mapping_storage.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final persistence = MappingPersistence(SharedPreferencesMappingStorage());
  final loadedMapping = await persistence.load();
  final draftPersistence = ConverterDraftPersistence();
  final loadedDraft = await draftPersistence.load();
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
      ],
      child: const JianpuKeyboardApp(),
    ),
  );
}
