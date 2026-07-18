/// Fieldbus topology model (Core §10.5.1): the physical bus tree the HMI renders
/// beside the logical module tree. Auto-detected from the master's diagnostics on
/// a real transport; the enum ordinals mirror the PLC E_NodeState/E_ChannelKind.
library;

/// E_NodeState — neutral bus-node state (EtherCAT INIT/PREOP/SAFEOP/OP map on).
enum NodeState { offline, init, preop, safeop, operational, fault }

enum ChannelDir { input, output }

enum ChannelKind { digital, analog }

class IoChannel {
  final String name;
  final String descriptionKey;
  final String address; // physical terminal/channel locator
  final String path; // unique channel path (force/audit identity)
  final String modulePath; // owning module path for cross-navigation
  final ChannelDir dir;
  final ChannelKind kind;
  final bool boolValue; // digital
  final double analogValue; // analog (scaled)
  final String unit;
  final bool forced;
  final bool quality; // true = good
  final bool faultActive;
  final String diagnosticKey;
  const IoChannel({
    required this.name,
    this.descriptionKey = '',
    this.address = '',
    required this.path,
    this.modulePath = '',
    required this.dir,
    required this.kind,
    this.boolValue = false,
    this.analogValue = 0,
    this.unit = '',
    this.forced = false,
    this.quality = true,
    this.faultActive = false,
    this.diagnosticKey = '',
  });
}

class BusNode {
  final String name;
  final String descriptionKey;
  final String typeId; // vendor/product
  final String address; // topological + logical
  final NodeState state;
  final bool linkOk;
  final bool mappingValid;
  final String mappingDiagnosticKey;
  final List<IoChannel> channels;
  final List<BusNode> children;
  const BusNode({
    required this.name,
    this.descriptionKey = '',
    required this.typeId,
    required this.address,
    this.state = NodeState.operational,
    this.linkOk = true,
    this.mappingValid = true,
    this.mappingDiagnosticKey = '',
    this.channels = const [],
    this.children = const [],
  });

  /// Worst state in this subtree (for ancestor colouring, like the module tree).
  NodeState get effectiveState {
    var worst = state;
    for (final c in children) {
      final cs = c.effectiveState;
      if (_severity(cs) > _severity(worst)) worst = cs;
    }
    return worst;
  }

  static int _severity(NodeState s) => switch (s) {
        NodeState.fault => 4,
        NodeState.offline => 3,
        NodeState.safeop => 2,
        NodeState.preop => 1,
        NodeState.init => 1,
        NodeState.operational => 0,
      };

  BusNode? find(String name_) {
    if (name == name_) return this;
    for (final c in children) {
      final hit = c.find(name_);
      if (hit != null) return hit;
    }
    return null;
  }
}
