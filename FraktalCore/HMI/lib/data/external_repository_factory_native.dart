library;

import '../domain/connection_settings.dart';
import 'opcua_native_client.dart';
import 'opcua_repository.dart';
import 'plc_repository.dart';

Future<PlcRepository> createExternalRepository(
    ConnectionSettings settings) async {
  final endpoint = Uri.parse(settings.endpoint);
  if (endpoint.scheme != 'opc.tcp') {
    throw UnsupportedError('Native direct connection requires an opc.tcp URI. '
        'WebSocket/REST endpoints use the Fraktal gateway repository.');
  }
  final client = await NativeOpcUaClient.connect(endpoint);
  return OpcUaRepository.connectWithClient(client);
}
