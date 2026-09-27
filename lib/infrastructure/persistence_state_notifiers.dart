import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'persistence_load_result.dart';
import 'storage_health.dart';

/// Shared transitions only; each domain supplies its own initial health.
abstract class StorageHealthNotifier extends Notifier<StorageHealth> {
  void markRawDataExported() => state = state.copyWith(rawDataExported: true);

  void markHealthy() =>
      state = const StorageHealth(status: PersistenceLoadStatus.normal);
}

class PersistenceWriteStateNotifier extends Notifier<PersistenceWriteState> {
  @override
  PersistenceWriteState build() =>
      const PersistenceWriteState(PersistenceWritePhase.idle);

  void saving() =>
      state = const PersistenceWriteState(PersistenceWritePhase.saving);
  void saved() =>
      state = const PersistenceWriteState(PersistenceWritePhase.saved);
  void failed(String message) => state =
      PersistenceWriteState(PersistenceWritePhase.failed, message: message);
}
