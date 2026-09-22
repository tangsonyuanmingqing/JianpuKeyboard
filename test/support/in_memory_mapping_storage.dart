import 'package:jianpu_keyboard/infrastructure/mapping_storage.dart';

/// Shared test storage for provider and widget tests.
class InMemoryMappingStorage implements MappingStorage {
  String? json;

  InMemoryMappingStorage({this.json});

  @override
  Future<String?> load() async => json;

  @override
  Future<void> save(String value) async {
    json = value;
  }

  @override
  Future<void> clear() async {
    json = null;
  }
}
