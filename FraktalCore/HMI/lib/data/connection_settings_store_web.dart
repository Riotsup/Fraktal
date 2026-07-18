// ignore_for_file: deprecated_member_use
library;

import 'dart:convert';
import 'dart:html' as html;
import '../domain/connection_settings.dart';
import 'connection_settings_store_base.dart';

ConnectionSettingsStore createConnectionSettingsStore() =>
    _WebConnectionSettingsStore();

class _WebConnectionSettingsStore implements ConnectionSettingsStore {
  static const _key = 'fraktal.hmi.connection.v1';

  @override
  Future<ConnectionSettings?> load() async {
    try {
      final raw = html.window.localStorage[_key];
      return raw == null ? null : ConnectionSettings.fromJson(jsonDecode(raw));
    } on Object {
      return null;
    }
  }

  @override
  Future<void> save(ConnectionSettings settings) async {
    html.window.localStorage[_key] = jsonEncode(settings.toJson());
  }

  @override
  Future<void> clear() async => html.window.localStorage.remove(_key);
}
