import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:jianpu_keyboard/features/converter/converter_draft_persistence.dart';
import 'package:jianpu_keyboard/features/converter/converter_input.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:jianpu_keyboard/infrastructure/app_data_store.dart';
import 'package:jianpu_keyboard/infrastructure/persistence_load_result.dart';

void main() {
  test('restores a song title together with the source draft', () async {
    final preferences = _PreferencesFake();
    final persistence = ConverterDraftPersistence(preferences: preferences);

    await persistence.save(
      const ConverterInput(scoreText: '3 4 5', lyricsText: '晨 光'),
      songTitle: '晨光',
      songId: 'song-1',
    );
    final restored = await persistence.load();

    expect(restored.songTitle, '晨光');
    expect(restored.songId, 'song-1');
    expect(restored.wasRestored, isTrue);
  });

  test('keeps older drafts readable when they have no song title', () async {
    final preferences = _PreferencesFake()
      ..values['jianpu_keyboard.converter_draft.v1'] = jsonEncode({
        'scoreText': '3 4 5',
        'lyricsText': '',
        'songId': null,
        'gridDocument': null,
        'editorMode': 'text',
      });

    final restored =
        await ConverterDraftPersistence(preferences: preferences).load();

    expect(restored.songTitle, isEmpty);
    expect(restored.input.scoreText, '3 4 5');
  });

  test('migrates a valid legacy draft once and leaves the legacy copy',
      () async {
    final directory = await Directory.systemTemp.createTemp('jianpu-draft-');
    addTearDown(() => directory.delete(recursive: true));
    final preferences = _PreferencesFake()
      ..values[ConverterDraftPersistence.legacyKey] = jsonEncode({
        'scoreText': '3 4 5',
        'lyricsText': '晨 光',
        'editorMode': 'text',
      });
    final store = AtomicFileStore(
      directoryProvider: FixedAppDataDirectoryProvider(directory),
    );
    final persistence = ConverterDraftPersistence(
      preferences: preferences,
      store: store,
    );

    final result = await persistence.load();

    expect(result.status, PersistenceLoadStatus.normal);
    expect(result.migrated, true);
    expect(result.input.scoreText, '3 4 5');
    expect(preferences.values, contains(ConverterDraftPersistence.legacyKey));
    expect(await store.read(ConverterDraftPersistence.primaryPath), isNotNull);
  });

  test('preserves corrupt primary draft for recovery and blocks writes',
      () async {
    final directory = await Directory.systemTemp.createTemp('jianpu-draft-');
    addTearDown(() => directory.delete(recursive: true));
    final store = AtomicFileStore(
      directoryProvider: FixedAppDataDirectoryProvider(directory),
    );
    await store.write(ConverterDraftPersistence.primaryPath, '{broken');

    final result = await ConverterDraftPersistence(store: store).load();

    expect(result.status, PersistenceLoadStatus.corrupt);
    expect(result.rawData, '{broken');
    expect(result.blocksWrites, true);
  });

  test('reports migration failure while retaining the decoded legacy draft',
      () async {
    final preferences = _PreferencesFake()
      ..values[ConverterDraftPersistence.legacyKey] = jsonEncode({
        'scoreText': '3',
        'lyricsText': '晨',
        'editorMode': 'text',
      });
    final persistence = ConverterDraftPersistence(
      preferences: preferences,
      store: _FailingStore(),
    );

    final result = await persistence.load();

    expect(result.status, PersistenceLoadStatus.migrationFailed);
    expect(result.input.scoreText, '3');
    expect(result.blocksWrites, true);
    expect(preferences.values, contains(ConverterDraftPersistence.legacyKey));
  });
}

class _FailingStore extends AtomicFileStore {
  @override
  Future<String?> read(String relativePath) async => null;

  @override
  Future<void> write(String relativePath, String contents) async {
    throw const FileSystemException('write failed');
  }
}

class _PreferencesFake extends Fake implements SharedPreferencesAsync {
  final Map<String, String> values = {};

  @override
  Future<String?> getString(String key) async => values[key];

  @override
  Future<void> setString(String key, String value) async {
    values[key] = value;
  }

  @override
  Future<void> remove(String key) async {
    values.remove(key);
  }
}
