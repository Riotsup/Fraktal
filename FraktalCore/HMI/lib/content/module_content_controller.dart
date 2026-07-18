library;

import 'dart:convert';
import 'package:flutter/foundation.dart';
import '../domain/types.dart';
import '../localization/localization_controller.dart';
import 'content_store.dart';

enum ModuleSection {
  information,
  operations,
  diagnostics,
  configuration,
  documentation,
  history,
}

class ModuleDocument {
  final String id;
  final String modulePath;
  final String fileName;
  final String titleKey;
  final String titleDefault;
  final Uint8List bytes;
  final DateTime uploadedAt;
  final String uploadedBy;

  const ModuleDocument({
    required this.id,
    required this.modulePath,
    required this.fileName,
    required this.titleKey,
    required this.titleDefault,
    required this.bytes,
    required this.uploadedAt,
    required this.uploadedBy,
  });

  Map<String, Object?> toJson() => {
        'id': id,
        'modulePath': modulePath,
        'fileName': fileName,
        'titleKey': titleKey,
        'titleDefault': titleDefault,
        'bytes': base64Encode(bytes),
        'uploadedAt': uploadedAt.toIso8601String(),
        'uploadedBy': uploadedBy,
      };

  static ModuleDocument? fromJson(Object? source) {
    if (source is! Map) return null;
    try {
      return ModuleDocument(
        id: source['id'] as String,
        modulePath: source['modulePath'] as String,
        fileName: source['fileName'] as String,
        titleKey: source['titleKey'] as String,
        titleDefault:
            source['titleDefault'] as String? ?? source['fileName'] as String,
        bytes: base64Decode(source['bytes'] as String),
        uploadedAt: DateTime.parse(source['uploadedAt'] as String),
        uploadedBy: source['uploadedBy'] as String,
      );
    } on Object {
      return null;
    }
  }
}

class ModuleContentController extends ChangeNotifier {
  static const maxPdfBytes = 20 * 1024 * 1024;
  final ContentStore store;
  final LocalizationController localization;
  final Map<String, List<ModuleDocument>> _documents = {};
  final Map<String, Map<ModuleSection, AccessLevel>> _policies = {};

  ModuleContentController({
    ContentStore? store,
    required this.localization,
  }) : store = store ?? MemoryContentStore();

  Future<void> load() async {
    final data = await store.load();
    final docs = data['documents'];
    if (docs is List) {
      for (final source in docs) {
        final document = ModuleDocument.fromJson(source);
        if (document == null) continue;
        localization.registerProjectDefault(
            document.titleKey, document.titleDefault);
        _documents.putIfAbsent(document.modulePath, () => []).add(document);
      }
    }
    final policies = data['policies'];
    if (policies is Map) {
      for (final module in policies.entries) {
        if (module.key is! String || module.value is! Map) continue;
        final sectionPolicy = <ModuleSection, AccessLevel>{};
        for (final item in (module.value as Map).entries) {
          final section = ModuleSection.values
              .where((value) => value.name == item.key)
              .firstOrNull;
          final level = AccessLevel.values
              .where((value) => value.name == item.value)
              .firstOrNull;
          if (section != null && level != null) sectionPolicy[section] = level;
        }
        _policies[module.key as String] = sectionPolicy;
      }
    }
  }

  List<ModuleDocument> documentsFor(String modulePath) =>
      List.unmodifiable(_documents[modulePath] ?? const []);

  AccessLevel requiredLevel(String modulePath, ModuleSection section) =>
      _policies[modulePath]?[section] ?? _defaultLevel(section);

  bool permits(String modulePath, ModuleSection section, AccessLevel current) =>
      current.index >= requiredLevel(modulePath, section).index;

  Future<void> setRequiredLevel(
      String modulePath, ModuleSection section, AccessLevel level) async {
    _policies.putIfAbsent(modulePath, () => {})[section] = level;
    await _persist();
    notifyListeners();
  }

  Future<ModuleDocument> addPdf({
    required String modulePath,
    required String fileName,
    required Uint8List bytes,
    required String title,
    required String uploadedBy,
  }) async {
    if (bytes.length > maxPdfBytes) {
      throw const FormatException('PDF too large');
    }
    if (bytes.length < 5 || ascii.decode(bytes.sublist(0, 5)) != '%PDF-') {
      throw const FormatException('Not a PDF');
    }
    final id = DateTime.now().microsecondsSinceEpoch.toString();
    final key = 'project.document.${_keyPart(modulePath)}.$id.title';
    final titleDefault = title.trim().isEmpty ? fileName : title.trim();
    localization.registerProjectDefault(key, titleDefault);
    final document = ModuleDocument(
      id: id,
      modulePath: modulePath,
      fileName: fileName,
      titleKey: key,
      titleDefault: titleDefault,
      bytes: bytes,
      uploadedAt: DateTime.now().toUtc(),
      uploadedBy: uploadedBy,
    );
    _documents.putIfAbsent(modulePath, () => []).add(document);
    await _persist();
    notifyListeners();
    return document;
  }

  Future<void> removeDocument(ModuleDocument document) async {
    _documents[document.modulePath]
        ?.removeWhere((item) => item.id == document.id);
    await _persist();
    notifyListeners();
  }

  Future<void> _persist() => store.save({
        'schemaVersion': 1,
        'documents': [
          for (final documents in _documents.values)
            for (final document in documents) document.toJson(),
        ],
        'policies': {
          for (final module in _policies.entries)
            module.key: {
              for (final policy in module.value.entries)
                policy.key.name: policy.value.name,
            },
        },
      });

  static AccessLevel _defaultLevel(ModuleSection section) => switch (section) {
        ModuleSection.information => AccessLevel.none,
        ModuleSection.operations => AccessLevel.operator,
        ModuleSection.diagnostics => AccessLevel.operator,
        ModuleSection.configuration => AccessLevel.engineer,
        ModuleSection.documentation => AccessLevel.operator,
        ModuleSection.history => AccessLevel.technician,
      };

  static String _keyPart(String value) => value
      .replaceAll(RegExp('[^A-Za-z0-9]+'), '_')
      .replaceAll(RegExp('_+'), '_');
}
