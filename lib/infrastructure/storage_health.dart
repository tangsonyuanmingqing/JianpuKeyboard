import 'persistence_load_result.dart';

class StorageHealth {
  const StorageHealth({
    required this.status,
    this.message,
    this.rawData,
    this.rawDataExported = false,
  });

  final PersistenceLoadStatus status;
  final String? message;
  final String? rawData;
  final bool rawDataExported;

  bool get blocksWrites =>
      status == PersistenceLoadStatus.corrupt ||
      status == PersistenceLoadStatus.migrationFailed;

  StorageHealth copyWith({
    PersistenceLoadStatus? status,
    String? message,
    String? rawData,
    bool? rawDataExported,
    bool clearMessage = false,
    bool clearRawData = false,
  }) =>
      StorageHealth(
        status: status ?? this.status,
        message: clearMessage ? null : message ?? this.message,
        rawData: clearRawData ? null : rawData ?? this.rawData,
        rawDataExported: rawDataExported ?? this.rawDataExported,
      );
}

enum PersistenceWritePhase { idle, saving, saved, failed }

class PersistenceWriteState {
  const PersistenceWriteState(this.phase, {this.message});

  final PersistenceWritePhase phase;
  final String? message;
}
