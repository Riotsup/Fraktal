library;

import 'connection_preflight_io.dart'
    if (dart.library.html) 'connection_preflight_web.dart' as implementation;
import 'connection_preflight_result.dart';

Future<ConnectionPreflightResult> preflightExternalEndpoint(
  Uri endpoint, {
  Duration timeout = const Duration(seconds: 3),
}) =>
    implementation.preflightExternalEndpoint(endpoint, timeout: timeout);
