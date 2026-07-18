library;

abstract class CatalogStore {
  Future<Map<String, Object?>> load();
  Future<void> save(Map<String, Object?> value);
}

class MemoryCatalogStore implements CatalogStore {
  Map<String, Object?> value;
  MemoryCatalogStore([Map<String, Object?>? value])
      : value = value ?? <String, Object?>{};

  @override
  Future<Map<String, Object?>> load() async => value;

  @override
  Future<void> save(Map<String, Object?> value) async {
    this.value = value;
  }
}
