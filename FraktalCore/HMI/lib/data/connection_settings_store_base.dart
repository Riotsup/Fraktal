library;

import '../domain/connection_settings.dart';

abstract class ConnectionSettingsStore {
  Future<ConnectionSettings?> load();
  Future<void> save(ConnectionSettings settings);
  Future<void> clear();
}

/// Deterministic store for tests and embedded hosts that provide persistence
/// outside Flutter.
class MemoryConnectionSettingsStore implements ConnectionSettingsStore {
  ConnectionSettings? value;
  MemoryConnectionSettingsStore([this.value]);

  @override
  Future<ConnectionSettings?> load() async => value;

  @override
  Future<void> save(ConnectionSettings settings) async => value = settings;

  @override
  Future<void> clear() async => value = null;
}
