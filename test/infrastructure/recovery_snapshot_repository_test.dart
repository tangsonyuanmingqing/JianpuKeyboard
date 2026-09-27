import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:jianpu_keyboard/infrastructure/app_data_store.dart';
import 'package:jianpu_keyboard/infrastructure/recovery_snapshot_repository.dart';

void main() {
  late Directory directory;
  late RecoverySnapshotRepository repository;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('jianpu-snapshots-');
    repository = RecoverySnapshotRepository(
      store: AtomicFileStore(
        directoryProvider: FixedAppDataDirectoryProvider(directory),
      ),
      retention: 3,
    );
  });

  tearDown(() async {
    if (directory.existsSync()) await directory.delete(recursive: true);
  });

  test('deduplicates automatic snapshots and retains the newest limit',
      () async {
    await repository.create(
      type: RecoverySnapshotType.library,
      payload: {'value': 0},
      source: RecoverySnapshotSource.automatic,
      deduplicate: true,
    );
    final duplicate = await repository.create(
      type: RecoverySnapshotType.library,
      payload: {'value': 0},
      source: RecoverySnapshotSource.automatic,
      deduplicate: true,
    );
    expect(duplicate, isNull);

    for (var value = 1; value <= 4; value++) {
      await Future<void>.delayed(const Duration(milliseconds: 1));
      await repository.create(
        type: RecoverySnapshotType.library,
        payload: {'value': value},
        source: RecoverySnapshotSource.manual,
        note: 'snapshot $value',
      );
    }

    final snapshots = await repository.list(RecoverySnapshotType.library);
    expect(snapshots, hasLength(3));
    expect((snapshots.first.payload as Map)['value'], 4);
    expect((snapshots.last.payload as Map)['value'], 2);
  });

  test('ignores a damaged snapshot without hiding valid snapshots', () async {
    await repository.create(
      type: RecoverySnapshotType.draft,
      payload: {'scoreText': '3'},
      source: RecoverySnapshotSource.manual,
    );
    final damaged = File('${directory.path}/backups/draft/damaged.json');
    await damaged.writeAsString('{not-json');

    expect(await repository.list(RecoverySnapshotType.draft), hasLength(1));
  });
}
