library;

import 'content_store_base.dart';
import 'content_store_stub.dart'
    if (dart.library.io) 'content_store_io.dart'
    if (dart.library.html) 'content_store_web.dart' as platform;

export 'content_store_base.dart';

ContentStore createContentStore() => platform.createContentStore();
