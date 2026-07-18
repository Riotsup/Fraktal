import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:fraktal_hmi/content/content_store.dart';
import 'package:fraktal_hmi/content/module_content_controller.dart';
import 'package:fraktal_hmi/domain/types.dart';
import 'package:fraktal_hmi/localization/localization_controller.dart';

void main() {
  test('section defaults and admin changes persist per module', () async {
    final store = MemoryContentStore();
    final localization =
        LocalizationController(enabledLanguages: {'en'}, activeLanguage: 'en');
    final first =
        ModuleContentController(store: store, localization: localization);

    expect(first.requiredLevel('StationA', ModuleSection.information),
        AccessLevel.none);
    expect(first.requiredLevel('StationA', ModuleSection.configuration),
        AccessLevel.engineer);
    await first.setRequiredLevel(
        'StationA', ModuleSection.documentation, AccessLevel.technician);

    final restored =
        ModuleContentController(store: store, localization: localization);
    await restored.load();
    expect(restored.requiredLevel('StationA', ModuleSection.documentation),
        AccessLevel.technician);
    expect(
        restored.permits(
            'StationA', ModuleSection.documentation, AccessLevel.operator),
        isFalse);
  });

  test('valid PDF and localizable title survive reload', () async {
    final store = MemoryContentStore();
    final localization =
        LocalizationController(enabledLanguages: {'en'}, activeLanguage: 'en');
    final first =
        ModuleContentController(store: store, localization: localization);
    final document = await first.addPdf(
      modulePath: 'StationA.Clamp',
      fileName: 'manual.pdf',
      bytes: Uint8List.fromList('%PDF-1.7\n%%EOF'.codeUnits),
      title: 'Clamp manual',
      uploadedBy: 'engineer',
    );
    expect(localization.resolve(document.titleKey), 'Clamp manual');

    final restoredLocalization =
        LocalizationController(enabledLanguages: {'en'}, activeLanguage: 'en');
    final restored = ModuleContentController(
        store: store, localization: restoredLocalization);
    await restored.load();
    final loaded = restored.documentsFor('StationA.Clamp').single;
    expect(loaded.bytes, document.bytes);
    expect(restoredLocalization.resolve(loaded.titleKey), 'Clamp manual');
  });

  test('non-PDF payload is rejected without committing', () async {
    final controller = ModuleContentController(
      store: MemoryContentStore(),
      localization: LocalizationController(
          enabledLanguages: {'en'}, activeLanguage: 'en'),
    );
    expect(
      () => controller.addPdf(
        modulePath: 'StationA',
        fileName: 'not.pdf',
        bytes: Uint8List.fromList('hello'.codeUnits),
        title: 'Invalid',
        uploadedBy: 'engineer',
      ),
      throwsFormatException,
    );
    expect(controller.documentsFor('StationA'), isEmpty);
  });
}
