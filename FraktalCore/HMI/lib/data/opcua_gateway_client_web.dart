// ignore_for_file: deprecated_member_use
library;

import 'dart:async';
import 'dart:convert';
import 'dart:html';
import 'opcua_session_client.dart';

/// Browser implementation of the Fraktal OPC UA gateway protocol. The gateway
/// owns the native OPC UA session and returns the exact same flat snapshot used
/// by the open62541 adapter.
class WebGatewayOpcUaClient implements OpcUaSessionClient {
  final WebSocket _socket;
  final Map<int, Completer<Object?>> _pending = {};
  late final StreamSubscription<MessageEvent> _messageSub;
  late final StreamSubscription<Event> _closeSub;
  int _nextId = 1;
  bool _closed = false;

  WebGatewayOpcUaClient._(this._socket) {
    _messageSub = _socket.onMessage.listen(_onMessage);
    _closeSub = _socket.onClose.listen((event) {
      _failAll(StateError('Fraktal OPC UA gateway connection closed.'));
    });
  }

  static Future<WebGatewayOpcUaClient> connect(
    Uri endpoint, {
    Duration timeout = const Duration(seconds: 5),
  }) async {
    final socket = WebSocket(endpoint.toString());
    final opened = Completer<void>();
    late StreamSubscription<Event> openSub;
    late StreamSubscription<Event> errorSub;
    openSub = socket.onOpen.listen((_) {
      if (!opened.isCompleted) opened.complete();
    });
    errorSub = socket.onError.listen((_) {
      if (!opened.isCompleted) {
        opened.completeError(
            StateError('Could not open Fraktal OPC UA WebSocket gateway.'));
      }
    });
    try {
      await opened.future.timeout(timeout);
    } finally {
      await openSub.cancel();
      await errorSub.cancel();
    }
    return WebGatewayOpcUaClient._(socket);
  }

  Future<Object?> _call(String method, [Map<String, Object?>? parameters]) {
    if (_closed) return Future.error(StateError('Gateway client is closed.'));
    final id = _nextId++;
    final completer = Completer<Object?>();
    _pending[id] = completer;
    _socket.send(jsonEncode({
      'protocol': 'fraktal.opcua.gateway.v1',
      'id': id,
      'method': method,
      'params': parameters ?? const <String, Object?>{},
    }));
    return completer.future.timeout(const Duration(seconds: 5), onTimeout: () {
      _pending.remove(id);
      throw TimeoutException('Gateway $method request timed out.');
    });
  }

  void _onMessage(MessageEvent event) {
    try {
      final decoded = jsonDecode('${event.data}');
      if (decoded is! Map) return;
      final id = decoded['id'];
      if (id is! int) return;
      final completer = _pending.remove(id);
      if (completer == null) return;
      if (decoded['ok'] == true) {
        completer.complete(decoded['result']);
      } else {
        completer.completeError(StateError('${decoded['error']}'));
      }
    } on Object catch (error) {
      _failAll(FormatException('Invalid gateway response: $error'));
    }
  }

  void _failAll(Object error) {
    for (final completer in _pending.values) {
      if (!completer.isCompleted) completer.completeError(error);
    }
    _pending.clear();
  }

  @override
  Future<Map<String, Object?>> snapshot() async {
    final result = await _call('snapshot');
    if (result is! Map)
      throw const FormatException('Gateway snapshot missing.');
    return Map<String, Object?>.from(result);
  }

  @override
  Future<bool> write(String path, OpcUaWriteType type, Object value) async =>
      (await _call('write', {
        'path': path,
        'valueType': type.name,
        'value': value,
      })) ==
      true;

  @override
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    await _messageSub.cancel();
    await _closeSub.cancel();
    _socket.close();
    _failAll(StateError('Gateway client closed.'));
  }
}
