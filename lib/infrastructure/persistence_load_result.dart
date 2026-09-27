enum PersistenceLoadStatus {
  normal,
  missing,
  corrupt,
  migrationFailed,
}

class PersistenceLoadResult<T> {
  const PersistenceLoadResult({
    required this.value,
    required this.status,
    this.message,
    this.rawData,
    this.migrated = false,
  });

  final T value;
  final PersistenceLoadStatus status;
  final String? message;
  final String? rawData;
  final bool migrated;

  bool get blocksWrites =>
      status == PersistenceLoadStatus.corrupt ||
      status == PersistenceLoadStatus.migrationFailed;
}
