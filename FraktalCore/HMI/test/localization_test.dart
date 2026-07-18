import 'package:flutter_test/flutter_test.dart';
import 'package:fraktal_hmi/localization/catalog_csv.dart';
import 'package:fraktal_hmi/localization/catalog_store.dart';
import 'package:fraktal_hmi/localization/localization_controller.dart';

void main() {
  test('CSV round-trips quotes, commas, and newlines', () {
    final csv = CatalogCsv.encode(
      scope: CatalogScope.project,
      locale: 'es',
      values: const {
        'project.test.message': 'Una línea, "dos"\ny tres',
      },
    );
    expect(
      CatalogCsv.decode(csv,
          expectedScope: CatalogScope.project, expectedLocale: 'es'),
      {'project.test.message': 'Una línea, "dos"\ny tres'},
    );
  });

  test('standard and project overrides persist independently', () async {
    final store = MemoryCatalogStore();
    final first = LocalizationController(
      store: store,
      enabledLanguages: {'es'},
      activeLanguage: 'es',
    );
    await first.importCsv(
      CatalogScope.standard,
      'es',
      CatalogCsv.encode(
        scope: CatalogScope.standard,
        locale: 'es',
        values: const {'std.common.save': 'Confirmar estándar'},
      ),
    );
    expect(first.resolve('std.common.save'), 'Confirmar estándar');
    await first.importCsv(
      CatalogScope.project,
      'es',
      CatalogCsv.encode(
        scope: CatalogScope.project,
        locale: 'es',
        values: const {'project.module.StationA.name': 'Estación A'},
      ),
    );
    expect(first.resolve('project.module.StationA.name'), 'Estación A');

    final restored = LocalizationController(
      store: store,
      enabledLanguages: {'es'},
      activeLanguage: 'es',
    );
    await restored.load();
    expect(restored.resolve('std.common.save'), 'Confirmar estándar');
    expect(restored.resolve('project.module.StationA.name'), 'Estación A');
  });

  test('CSV rejects wrong scope and duplicate keys', () {
    const duplicate = 'schemaVersion,scope,locale,key,value\r\n'
        '1,standard,en,std.common.save,Save\r\n'
        '1,standard,en,std.common.save,Again\r\n';
    expect(
      () => CatalogCsv.decode(duplicate,
          expectedScope: CatalogScope.standard, expectedLocale: 'en'),
      throwsFormatException,
    );
    final wrongScope = CatalogCsv.encode(
      scope: CatalogScope.project,
      locale: 'en',
      values: const {'project.key': 'Value'},
    );
    expect(
      () => CatalogCsv.decode(wrongScope,
          expectedScope: CatalogScope.standard, expectedLocale: 'en'),
      throwsFormatException,
    );
  });
}
