library;

import 'connection_preflight_result.dart';

Future<ConnectionPreflightResult> preflightExternalEndpoint(
  Uri endpoint, {
  required Duration timeout,
}) async {
  final port = endpoint.hasPort
      ? endpoint.port
      : switch (endpoint.scheme) {
          'ws' || 'http' => 80,
          'wss' || 'https' => 443,
          _ => 0,
        };
  return ConnectionPreflightResult(
    host: endpoint.host,
    port: port,
    reachable: true,
    elapsed: Duration.zero,
    detail:
        'Browser TCP preflight skipped; the WebSocket/HTTP adapter owns it.',
  );
}
