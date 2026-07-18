import 'package:flutter/widgets.dart';
import 'data/connection_settings_store.dart';
import 'data/repository_factory.dart';
import 'content/content_store.dart';
import 'content/module_content_controller.dart';
import 'localization/catalog_store.dart';
import 'localization/localization_controller.dart';
import 'ui/connection_bootstrap.dart';

export 'ui/fraktal_hmi_app.dart';

void main() {
  final localization = LocalizationController(store: createCatalogStore());
  runApp(ConnectionBootstrap(
    store: createConnectionSettingsStore(),
    repositoryFactory: createRepository,
    localization: localization,
    content: ModuleContentController(
      store: createContentStore(),
      localization: localization,
    ),
  ));
}
