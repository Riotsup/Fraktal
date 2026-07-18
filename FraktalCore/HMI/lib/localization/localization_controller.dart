library;

import 'dart:ui';
import 'package:flutter/foundation.dart';
import 'catalog_csv.dart';
import 'catalog_store.dart';
import 'default_catalogs.dart';

class LocalizationController extends ChangeNotifier {
  final CatalogStore store;
  final Map<String, Map<String, String>> _standardOverrides = {};
  final Map<String, Map<String, String>> _projectOverrides = {};
  final Map<String, String> _runtimeStandardDefaults = {};
  final Map<String, String> _runtimeProjectDefaults = Map.of(projectEnglish);

  Set<String> enabledLanguages;
  String activeLanguage;

  LocalizationController({
    CatalogStore? store,
    Set<String>? enabledLanguages,
    String? activeLanguage,
  })  : store = store ?? MemoryCatalogStore(),
        enabledLanguages = enabledLanguages ?? {_detectedLanguage()},
        activeLanguage = activeLanguage ?? _detectedLanguage();

  Locale get locale => Locale(activeLanguage);

  static String _detectedLanguage() {
    final detected = PlatformDispatcher.instance.locale.languageCode;
    return availableLanguages.containsKey(detected) ? detected : 'en';
  }

  Future<void> load() async {
    final data = await store.load();
    _readOverrides(data['standard'], _standardOverrides);
    _readOverrides(data['project'], _projectOverrides);
  }

  void configure({
    required Iterable<String> enabled,
    required String active,
  }) {
    final valid = enabled.where(availableLanguages.containsKey).toSet();
    if (valid.isEmpty) valid.add('en');
    enabledLanguages = valid;
    activeLanguage = valid.contains(active) ? active : valid.first;
    notifyListeners();
  }

  void setActiveLanguage(String language) {
    if (!enabledLanguages.contains(language) || activeLanguage == language) {
      return;
    }
    activeLanguage = language;
    notifyListeners();
  }

  String resolve(String keyOrDefault, [Map<String, Object?> args = const {}]) {
    final isExplicitKey = keyOrDefault.startsWith('std.') ||
        keyOrDefault.startsWith('project.') ||
        _knownKey(keyOrDefault);
    final key = isExplicitKey ? keyOrDefault : _autoKey(keyOrDefault);
    if (!isExplicitKey) _runtimeStandardDefaults[key] = keyOrDefault;

    final fallback = _englishValue(key) ?? (isExplicitKey ? key : keyOrDefault);
    final value = key.startsWith('project.')
        ? (_projectOverrides[activeLanguage]?[key] ??
            _projectDefault(activeLanguage, key) ??
            fallback)
        : (_standardOverrides[activeLanguage]?[key] ??
            _standardDefault(activeLanguage, key) ??
            fallback);
    return _interpolate(value, args);
  }

  void registerProjectDefault(String key, String english) {
    if (!key.startsWith('project.')) {
      throw ArgumentError.value(key, 'key', 'Project keys start with project.');
    }
    _runtimeProjectDefaults[key] = english;
  }

  Map<String, String> exportValues(CatalogScope scope, String language) {
    final defaults = scope == CatalogScope.standard
        ? <String, String>{...standardEnglish, ..._runtimeStandardDefaults}
        : Map<String, String>.of(_runtimeProjectDefaults);
    final result = <String, String>{};
    for (final entry in defaults.entries) {
      final overrides = scope == CatalogScope.project
          ? _projectOverrides[language]
          : _standardOverrides[language];
      result[entry.key] = overrides?[entry.key] ??
          (language == 'es'
              ? (scope == CatalogScope.standard
                  ? standardSpanish[entry.key]
                  : projectSpanish[entry.key])
              : null) ??
          entry.value;
    }
    return result;
  }

  String exportCsv(CatalogScope scope, String language) => CatalogCsv.encode(
        scope: scope,
        locale: language,
        values: exportValues(scope, language),
      );

  Future<void> importCsv(
      CatalogScope scope, String language, String csv) async {
    final values =
        CatalogCsv.decode(csv, expectedScope: scope, expectedLocale: language);
    final target =
        scope == CatalogScope.standard ? _standardOverrides : _projectOverrides;
    target[language] = values;
    await _persist();
    notifyListeners();
  }

  bool _knownKey(String key) =>
      standardEnglish.containsKey(key) ||
      _runtimeProjectDefaults.containsKey(key);

  String? _englishValue(String key) =>
      _runtimeProjectDefaults[key] ??
      standardEnglish[key] ??
      _runtimeStandardDefaults[key];

  String? _standardDefault(String language, String key) {
    if (language == 'es') return standardSpanish[key] ?? standardEnglish[key];
    return standardEnglish[key] ?? _runtimeStandardDefaults[key];
  }

  String? _projectDefault(String language, String key) {
    if (language == 'es')
      return projectSpanish[key] ?? _runtimeProjectDefaults[key];
    return _runtimeProjectDefaults[key];
  }

  Future<void> _persist() => store.save({
        'schemaVersion': 1,
        'standard': _standardOverrides,
        'project': _projectOverrides,
      });

  static void _readOverrides(
      Object? source, Map<String, Map<String, String>> target) {
    if (source is! Map) return;
    for (final entry in source.entries) {
      if (entry.key is! String || entry.value is! Map) continue;
      target[entry.key as String] = (entry.value as Map).map(
        (key, value) => MapEntry(key.toString(), value.toString()),
      );
    }
  }

  static String _interpolate(String value, Map<String, Object?> args) {
    var result = value;
    for (final entry in args.entries) {
      result = result.replaceAll('{${entry.key}}', '${entry.value ?? ''}');
    }
    return result;
  }

  static String _autoKey(String source) {
    var hash = 0x811c9dc5;
    for (final code in source.codeUnits) {
      hash ^= code;
      hash = (hash * 0x01000193) & 0xffffffff;
    }
    return 'std.auto.${hash.toRadixString(16).padLeft(8, '0')}';
  }
}
