library;

import 'dart:async';
import 'dart:io';
import 'connection_preflight_result.dart';

Future<ConnectionPreflightResult> preflightExternalEndpoint(
  Uri endpoint, {
  required Duration timeout,
}) async {
  final port = _effectivePort(endpoint);
  final watch = Stopwatch()..start();
  Socket? socket;
  try {
    socket = await Socket.connect(endpoint.host, port, timeout: timeout);
    return ConnectionPreflightResult(
      host: endpoint.host,
      port: port,
      reachable: true,
      elapsed: watch.elapsed,
      detail: 'TCP listener accepted the connection.',
    );
  } on TimeoutException {
    return ConnectionPreflightResult(
      host: endpoint.host,
      port: port,
      reachable: false,
      elapsed: watch.elapsed,
      detail: 'TCP connection timed out after ${timeout.inSeconds}s.',
    );
  } on SocketException catch (error) {
    return ConnectionPreflightResult(
      host: endpoint.host,
      port: port,
      reachable: false,
      elapsed: watch.elapsed,
      detail: error.message,
    );
  } finally {
    socket?.destroy();
  }
}

int _effectivePort(Uri endpoint) {
  if (endpoint.hasPort) return endpoint.port;
  return switch (endpoint.scheme) {
    'opc.tcp' => 4840,
    'ws' || 'http' => 80,
    'wss' || 'https' => 443,
    _ => 0,
  };
}
