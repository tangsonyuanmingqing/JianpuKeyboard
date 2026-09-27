import 'dart:convert';
import 'dart:io';

import 'app_data_store.dart';

enum RecoverySnapshotType { library, draft }

enum RecoverySnapshotSource { automatic, manual, beforeRestore }

class RecoverySnapshot {
  const RecoverySnapshot({
    required this.id,
    required this.type,
    required this.createdAt,
    required this.source,
    required this.payload,
    this.note,
  });

  final String id;
  final RecoverySnapshotType type;
  final DateTime createdAt;
  final RecoverySnapshotSource source;
  final Object? payload;
  final String? note;

  Map<String, Object?> toJson() => {
        'version': 1,
        'id': id,
        'type': type.name,
        'createdAt': createdAt.toUtc().toIso8601String(),
        'source': source.name,
        'note': note,
        'payload': payload,
      };

  static RecoverySnapshot? fromJson(Object? value) {
    if (value is! Map) return null;
    if (value['version'] != 1 ||
        value['id'] is! String ||
        value['type'] is! String ||
        value['createdAt'] is! String ||
        value['source'] is! String ||
        !value.containsKey('payload')) {
      return null;
    }
    final type = RecoverySnapshotType.values
        .where((item) => item.name == value['type'])
        .firstOrNull;
    final source = RecoverySnapshotSource.values
        .where((item) => item.name == value['source'])
        .firstOrNull;
    final createdAt = DateTime.tryParse(value['createdAt'] as String);
    if (type == null || source == null || createdAt == null) return null;
    return RecoverySnapshot(
      id: value['id'] as String,
      type: type,
      createdAt: createdAt.toUtc(),
      source: source,
      note: value['note'] is String ? value['note'] as String : null,
      payload: value['payload'],
    );
  }
}

class RecoverySnapshotRepository {
  RecoverySnapshotRepository({AtomicFileStore? store, this.retention = 20})
      : store = store ?? AtomicFileStore();

  final AtomicFileStore store;
  final int retention;
  final SerialOperationQueue _queue = SerialOperationQueue();

  Future<List<RecoverySnapshot>> list(RecoverySnapshotType type) async {
    final root = await store.directoryProvider.directory();
    final directory = Directory(
      '${root.path}${Platform.pathSeparator}backups'
      '${Platform.pathSeparator}${type.name}',
    );
    if (!directory.existsSync()) return const [];
    final snapshots = <RecoverySnapshot>[];
    await for (final entity in directory.list()) {
      if (entity is! File || !entity.path.endsWith('.json')) continue;
      try {
        final decoded = jsonDecode(await entity.readAsString());
        final snapshot = RecoverySnapshot.fromJson(decoded);
        if (snapshot != null && snapshot.type == type) snapshots.add(snapshot);
      } on Object {
        // One damaged snapshot must not hide the remaining valid snapshots.
      }
    }
    snapshots.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return List.unmodifiable(snapshots);
  }

  Future<RecoverySnapshot?> create({
    required RecoverySnapshotType type,
    required Object? payload,
    required RecoverySnapshotSource source,
    String? note,
    bool deduplicate = false,
  }) {
    return _queue.run(() async {
      if (deduplicate) {
        final current = await list(type);
        if (current.isNotEmpty &&
            jsonEncode(current.first.payload) == jsonEncode(payload)) {
          return null;
        }
      }
      final now = DateTime.now().toUtc();
      final id = '${now.microsecondsSinceEpoch}';
      final snapshot = RecoverySnapshot(
        id: id,
        type: type,
        createdAt: now,
        source: source,
        note: note?.trim().isEmpty == true ? null : note?.trim(),
        payload: payload,
      );
      await store.write(
        'backups/${type.name}/$id.json',
        jsonEncode(snapshot.toJson()),
      );
      await _prune(type);
      return snapshot;
    });
  }

  Future<void> delete(RecoverySnapshot snapshot) =>
      _queue.run(() => store.delete(
            'backups/${snapshot.type.name}/${snapshot.id}.json',
          ));

  Future<void> _prune(RecoverySnapshotType type) async {
    final snapshots = await list(type);
    for (final snapshot in snapshots.skip(retention)) {
      await store.delete('backups/${type.name}/${snapshot.id}.json');
    }
  }

  Future<void> flush() => _queue.flush();
}
