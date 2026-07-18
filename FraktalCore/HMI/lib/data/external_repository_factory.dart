library;

import '../domain/connection_settings.dart';
import 'external_repository_factory_stub.dart'
    if (dart.library.io) 'external_repository_factory_native.dart'
    if (dart.library.html) 'external_repository_factory_web.dart' as platform;
import 'plc_repository.dart';

Future<PlcRepository> createExternalRepository(ConnectionSettings settings) =>
    platform.createExternalRepository(settings);
