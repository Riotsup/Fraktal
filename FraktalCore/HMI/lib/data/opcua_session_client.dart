library;

enum OpcUaWriteType { boolean, int32, uint32, int64, doubleValue, string }

/// Transport-neutral snapshot/write session used by the generic repository.
/// Native platforms implement it with open62541; Web implements it over the
/// Fraktal WebSocket gateway because browsers cannot open OPC UA TCP sockets.
abstract class OpcUaSessionClient {
  Future<Map<String, Object?>> snapshot();
  Future<bool> write(String path, OpcUaWriteType type, Object value);
  Future<void> close();
}
