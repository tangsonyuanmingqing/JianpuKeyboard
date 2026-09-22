/// Failure while reading, writing, or clearing the local mapping store.
///
/// No saved mapping is not this error: [MappingStorage.load] returns null.
/// Text that cannot be decoded as a mapping is also not this error. The
/// caller decodes the stored string and handles that failure separately.
class MappingStorageException implements Exception {
  final String message;
  final Object? cause;

  const MappingStorageException(this.message, {this.cause});

  @override
  String toString() => 'MappingStorageException: $message';
}

/// Stores the raw keyboard-mapping JSON text.
///
/// Implementations replace the previous value on [save]. They do not parse
/// JSON, validate keys, choose a default mapping, or persist warnings.
/// Platform code stays behind this type: the interface has no file,
/// preferences, or operating-system API.
abstract interface class MappingStorage {
  /// Returns the stored JSON text, or null when nothing is stored.
  ///
  /// A platform failure throws [MappingStorageException] and is not reported
  /// as null.
  Future<String?> load();

  /// Replaces any stored text with [json].
  ///
  /// [json] is stored as given. This method does not check that it is valid
  /// mapping JSON.
  Future<void> save(String json);

  /// Removes the stored text.
  ///
  /// Completes normally when nothing is stored.
  Future<void> clear();
}
