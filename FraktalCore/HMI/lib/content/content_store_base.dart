library;

abstract class ContentStore {
  Future<Map<String, Object?>> load();
  Future<void> save(Map<String, Object?> value);
}

class MemoryContentStore implements ContentStore {
  Map<String, Object?> value;
  MemoryContentStore([Map<String, Object?>? value])
      : value = value ?? <String, Object?>{};

  @override
  Future<Map<String, Object?>> load() async => value;

  @override
  Future<void> save(Map<String, Object?> value) async {
    this.value = value;
  }
}
