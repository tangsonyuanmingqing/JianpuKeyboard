import 'dart:async';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

abstract interface class AppDataDirectoryProvider {
  Future<Directory> directory();
}

class PlatformAppDataDirectoryProvider implements AppDataDirectoryProvider {
  const PlatformAppDataDirectoryProvider();

  @override
  Future<Directory> directory() async {
    final base = await getApplicationSupportDirectory();
    return Directory('${base.path}${Platform.pathSeparator}jianpu_keyboard');
  }
}

class FixedAppDataDirectoryProvider implements AppDataDirectoryProvider {
  const FixedAppDataDirectoryProvider(this.root);

  final Directory root;

  @override
  Future<Directory> directory() async => root;
}

class AtomicFileStore {
  AtomicFileStore({AppDataDirectoryProvider? directoryProvider})
      : directoryProvider =
            directoryProvider ?? const PlatformAppDataDirectoryProvider();

  final AppDataDirectoryProvider directoryProvider;

  Future<File> file(String relativePath) async {
    final root = await directoryProvider.directory();
    return File('${root.path}${Platform.pathSeparator}$relativePath');
  }

  Future<String?> read(String relativePath) async {
    final target = await file(relativePath);
    final previous = File('${target.path}.previous');
    if (!target.existsSync() && previous.existsSync()) {
      await previous.rename(target.path);
    }
    return target.existsSync() ? target.readAsString() : null;
  }

  Future<void> write(String relativePath, String contents) async {
    final target = await file(relativePath);
    await target.parent.create(recursive: true);
    final temporary = File('${target.path}.tmp');
    final previous = File('${target.path}.previous');

    if (temporary.existsSync()) await temporary.delete();
    await temporary.writeAsString(contents, flush: true);

    try {
      if (previous.existsSync()) await previous.delete();
      if (target.existsSync()) {
        await target.copy(previous.path);
      }
      await temporary.rename(target.path);
      if (previous.existsSync()) await previous.delete();
    } on Object {
      if (!target.existsSync() && previous.existsSync()) {
        await previous.rename(target.path);
      }
      if (temporary.existsSync()) await temporary.delete();
      rethrow;
    }
  }

  Future<void> delete(String relativePath) async {
    final target = await file(relativePath);
    if (target.existsSync()) await target.delete();
    final temporary = File('${target.path}.tmp');
    if (temporary.existsSync()) await temporary.delete();
    final previous = File('${target.path}.previous');
    if (previous.existsSync()) await previous.delete();
  }
}

class SerialOperationQueue {
  Future<void> _tail = Future<void>.value();

  Future<T> run<T>(Future<T> Function() action) {
    final completer = Completer<T>();
    _tail = _tail.then((_) async {
      try {
        completer.complete(await action());
      } on Object catch (error, stackTrace) {
        completer.completeError(error, stackTrace);
      }
    });
    return completer.future;
  }

  Future<void> flush() => _tail;
}
