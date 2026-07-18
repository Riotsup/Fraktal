library;

import 'catalog_store_base.dart';
import 'catalog_store_stub.dart'
    if (dart.library.io) 'catalog_store_io.dart'
    if (dart.library.html) 'catalog_store_web.dart' as platform;

export 'catalog_store_base.dart';

CatalogStore createCatalogStore() => platform.createCatalogStore();
