library;

/// Result of the transport-level TCP probe performed before a repository is
/// created. A successful probe proves only that a listener accepted TCP; it
/// does not prove that the expected application protocol is available.
class ConnectionPreflightResult {
  final String host;
  final int port;
  final bool reachable;
  final Duration elapsed;
  final String detail;

  const ConnectionPreflightResult({
    required this.host,
    required this.port,
    required this.reachable,
    required this.elapsed,
    required this.detail,
  });
}
