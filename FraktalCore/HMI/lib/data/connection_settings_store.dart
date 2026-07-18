library;

import 'connection_settings_store_base.dart';
import 'connection_settings_store_stub.dart'
    if (dart.library.io) 'connection_settings_store_io.dart'
    if (dart.library.html) 'connection_settings_store_web.dart' as platform;

export 'connection_settings_store_base.dart';

ConnectionSettingsStore createConnectionSettingsStore() =>
    platform.createConnectionSettingsStore();
