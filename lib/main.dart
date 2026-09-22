import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app/app.dart';
import 'features/converter/converter_providers.dart';
import 'features/converter/mapping_persistence.dart';
import 'infrastructure/shared_preferences_mapping_storage.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final persistence = MappingPersistence(SharedPreferencesMappingStorage());
  final loaded = await persistence.load();
  runApp(
    ProviderScope(
      overrides: [
        mappingPersistenceProvider.overrideWithValue(persistence),
        initialMappingDraftProvider.overrideWithValue(loaded.draft),
        initialMappingPersistenceMessageProvider.overrideWithValue(
          loaded.message,
        ),
      ],
      child: const JianpuKeyboardApp(),
    ),
  );
}
