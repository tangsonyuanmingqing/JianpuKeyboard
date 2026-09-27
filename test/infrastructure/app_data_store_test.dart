import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:jianpu_keyboard/infrastructure/app_data_store.dart';

void main() {
  late Directory directory;
  late AtomicFileStore store;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('jianpu-atomic-');
    store = AtomicFileStore(
      directoryProvider: FixedAppDataDirectoryProvider(directory),
    );
  });

  tearDown(() async {
    if (directory.existsSync()) await directory.delete(recursive: true);
  });

  test('atomically replaces an existing file and removes staging files',
      () async {
    await store.write('storage/value.json', '{"value":1}');
    await store.write('storage/value.json', '{"value":2}');

    expect(await store.read('storage/value.json'), '{"value":2}');
    expect(
        File('${directory.path}/storage/value.json.tmp').existsSync(), false);
    expect(
      File('${directory.path}/storage/value.json.previous').existsSync(),
      false,
    );
  });

  test('serial queue continues after a failed operation', () async {
    final queue = SerialOperationQueue();
    await expectLater(
      queue.run<void>(() async => throw StateError('failed')),
      throwsStateError,
    );
    expect(await queue.run(() async => 2), 2);
    await queue.flush();
  });

  test('keeps the previous file when replacement staging fails', () async {
    await store.write('storage/value.json', '{"value":1}');
    await Directory('${directory.path}/storage/value.json.previous').create();

    await expectLater(
      store.write('storage/value.json', '{"value":2}'),
      throwsA(isA<FileSystemException>()),
    );

    expect(await store.read('storage/value.json'), '{"value":1}');
  });

  test('recovers a previous file left by an interrupted replacement', () async {
    final previous = File('${directory.path}/storage/value.json.previous');
    await previous.parent.create(recursive: true);
    await previous.writeAsString('{"value":1}', flush: true);

    expect(await store.read('storage/value.json'), '{"value":1}');
    expect(File('${directory.path}/storage/value.json').existsSync(), true);
    expect(previous.existsSync(), false);
  });

  test('explicit deletion removes staging files so data cannot reappear',
      () async {
    final target = File('${directory.path}/storage/value.json');
    await target.parent.create(recursive: true);
    await target.writeAsString('{"value":2}');
    await File('${target.path}.tmp').writeAsString('{"value":3}');
    await File('${target.path}.previous').writeAsString('{"value":1}');

    await store.delete('storage/value.json');

    expect(await store.read('storage/value.json'), isNull);
    expect(File('${target.path}.tmp').existsSync(), false);
    expect(File('${target.path}.previous').existsSync(), false);
  });
}
