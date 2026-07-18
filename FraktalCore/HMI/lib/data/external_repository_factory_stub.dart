library;

import '../domain/connection_settings.dart';
import 'plc_repository.dart';

Future<PlcRepository> createExternalRepository(ConnectionSettings settings) =>
    Future.error(UnsupportedError(
        'No external Fraktal transport is available on this platform.'));
