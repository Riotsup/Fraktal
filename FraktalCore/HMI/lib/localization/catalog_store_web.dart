// ignore_for_file: deprecated_member_use
library;

import 'dart:convert';
import 'dart:html' as html;
import 'catalog_store_base.dart';

CatalogStore createCatalogStore() => _WebCatalogStore();

class _WebCatalogStore implements CatalogStore {
  static const _key = 'fraktal.hmi.languageCatalogs.v1';

  @override
  Future<Map<String, Object?>> load() async {
    try {
      final raw = html.window.localStorage[_key];
      final value = raw == null ? null : jsonDecode(raw);
      return value is Map ? Map<String, Object?>.from(value) : {};
    } on Object {
      return {};
    }
  }

  @override
  Future<void> save(Map<String, Object?> value) async {
    html.window.localStorage[_key] = jsonEncode(value);
  }
}
