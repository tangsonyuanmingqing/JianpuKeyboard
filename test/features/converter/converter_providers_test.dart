import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jianpu_keyboard/features/converter/converter_draft_persistence.dart';
import 'package:jianpu_keyboard/features/converter/converter_input.dart';
import 'package:jianpu_keyboard/features/converter/converter_providers.dart';
import 'package:jianpu_keyboard/features/converter/smart_grid_document.dart';
import 'package:jianpu_keyboard/infrastructure/app_data_store.dart';
import 'package:jianpu_keyboard/infrastructure/recovery_providers.dart';
import 'package:jianpu_keyboard/infrastructure/recovery_snapshot_repository.dart';

void main() {
  test('creates the next draft snapshot when the interval elapses', () async {
    final persistence = _DraftPersistenceFake();
    final snapshots = _SnapshotRepositoryFake();
    final container = ProviderContainer(overrides: [
      converterDraftPersistenceProvider.overrideWithValue(persistence),
      recoverySnapshotRepositoryProvider.overrideWithValue(snapshots),
      draftSaveDelayProvider.overrideWithValue(const Duration(milliseconds: 5)),
      draftSnapshotIntervalProvider
          .overrideWithValue(const Duration(milliseconds: 60)),
    ]);
    addTearDown(container.dispose);

    container.read(converterInputProvider.notifier).setScoreText('3');
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(snapshots.created, 1);

    container.read(converterInputProvider.notifier).setScoreText('4');
    await Future<void>.delayed(const Duration(milliseconds: 90));

    expect(snapshots.created, 2);
    expect((snapshots.payloads.last as Map)['scoreText'], '4');
  });

  test('clearing cancels an older delayed save', () async {
    final directory = await Directory.systemTemp.createTemp('jianpu-clear-');
    addTearDown(() => directory.delete(recursive: true));
    final store = AtomicFileStore(
      directoryProvider: FixedAppDataDirectoryProvider(directory),
    );
    final persistence = ConverterDraftPersistence(store: store);
    final container = ProviderContainer(overrides: [
      converterDraftPersistenceProvider.overrideWithValue(persistence),
      recoverySnapshotRepositoryProvider
          .overrideWithValue(_SnapshotRepositoryFake()),
      draftSaveDelayProvider
          .overrideWithValue(const Duration(milliseconds: 30)),
    ]);
    addTearDown(container.dispose);

    container.read(converterInputProvider.notifier).setScoreText('old');
    container.read(converterInputProvider.notifier).clear();
    await Future<void>.delayed(const Duration(milliseconds: 60));
    await persistence.flush();

    expect(await store.read(ConverterDraftPersistence.primaryPath), isNull);
  });
}

class _DraftPersistenceFake extends ConverterDraftPersistence {
  @override
  Future<void> save(
    ConverterInput input, {
    String songTitle = '',
    String? songId,
    SmartGridDocument? gridDocument,
    String editorMode = 'text',
  }) async {}

  @override
  Future<void> flush() async {}
}

class _SnapshotRepositoryFake extends RecoverySnapshotRepository {
  int created = 0;
  final List<Object?> payloads = [];

  @override
  Future<RecoverySnapshot?> create({
    required RecoverySnapshotType type,
    required Object? payload,
    required RecoverySnapshotSource source,
    String? note,
    bool deduplicate = false,
  }) async {
    created++;
    payloads.add(payload);
    return null;
  }

  @override
  Future<void> flush() async {}
}
