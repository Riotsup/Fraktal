/// The discovered module tree — mirror of the exposed namespace (Core 3.10/3.13):
/// a node exists iff the PLC symbol carries `Status : ST_ModuleStatus`.
library;

import 'types.dart';

class ModuleNode {
  final String path; // OPC UA browse path = identity (Core 4.8)
  final String name;
  final String displayNameKey;
  final String descriptionKey;
  final ModuleType type;
  final ExecState state;
  final bool faultActive;
  final String
      message; // Status.Diagnostic.Description (Unit: Pending overlays)
  final String diagnosticIoTag;
  final String diagnosticIoAddress;
  final bool tileEnable;
  final List<ModuleNode> children;
  final String controlDomainId; // §9.8; empty means no assigned arrangement
  final String controlDomainName;
  final List<String> controlDomainMembers;

  // Unit-only extras (empty/zero elsewhere)
  final String modelCode;
  final List<String>
      availableModels; // §3.8 optional PLC-published recipe catalog
  final UnitMode? modeActive;
  final int goodCount;
  final int nokCount;
  final bool blocking; // AlarmLog.Blocking -> banner + Start disabled
  final List<AlarmEvent> activeEvents; // AlarmLog.Active (this node's log)
  final List<AlarmEvent> ringEvents; // AlarmLog.Ring newest-first
  final AccessSession? access; // root Units only (per-root manager, 7.7)

  // optional typed facets (annex data) — null when the module doesn't publish them
  final LinkFacet? link; // Annex D
  final PartFacet? part; // Annex E
  final PackMLState? packML; // Annex F
  final MotionFacet? motion; // Annex G / I
  final SafetyFacet? safety; // §9.8 read-only certified-safety mirror
  final ControlPowerFacet? controlPower; // §9.8 Control On + power groups
  final CycleProfile? cycle; // §8.11.4 (Units)
  final List<CycleSummary> cycleHistory; // §8.11.4 trend ring, oldest..newest (Units)
  final Duration lastCycleTime; // §8.11.1 (Units)
  final Duration minCycleTime; // §8.11.1 rolling best since reset (Units)
  final List<CommandTiming> commandTimings; // §8.11.4(a) module Timing.Rows (CM/EM)
  final MachineState? machineState; // §8.11.3 (Units)
  final int reworkCount; // §8.11.2 (Units)
  final DecisionRequest? decision; // §6.11 (Units)
  final List<CfgField> config; // §3.8a editable persistent data
  final StepInfo? step; // §6.5/§6.9 current step (Units)
  final List<StepStat> stepStats; // §8.11.4 Pareto (Units)
  final List<CommandInfo>
      commands; // §7.6.1 published manual-command catalog (CM/EM)
  final Nameplate? nameplate; // §3.10.1 asset identity (null = none published)
  final bool running; // §3.4 — a mode sequence is executing (BUSY)
  final bool
      stopPending; // §3.4 — stop requested, sequence still finishing (blink)
  final RunStyle runStyle; // §3.4.2 active run style (Units)
  final List<UnitMode> supportedModes; // §3.7 _M_Supports (Units)
  final List<RunStyle>
      supportedRunStyles; // §3.4.2 which run styles this mode allows
  final Map<UnitMode, ModePolicy> modePolicy; // §3.4.1 per-mode switch policy
  final OeeSnapshot? oee; // §8.5.1 (Units)
  final List<AlarmMeta> alarmMeta; // §8.9 rationalization catalog (Units)

  const ModuleNode({
    required this.path,
    required this.name,
    this.displayNameKey = '',
    this.descriptionKey = '',
    required this.type,
    this.state = ExecState.ready,
    this.faultActive = false,
    this.message = '',
    this.diagnosticIoTag = '',
    this.diagnosticIoAddress = '',
    this.tileEnable = true,
    this.children = const [],
    this.controlDomainId = '',
    this.controlDomainName = '',
    this.controlDomainMembers = const [],
    this.modelCode = '',
    this.availableModels = const [],
    this.modeActive,
    this.goodCount = 0,
    this.nokCount = 0,
    this.blocking = false,
    this.activeEvents = const [],
    this.ringEvents = const [],
    this.access,
    this.link,
    this.part,
    this.packML,
    this.motion,
    this.safety,
    this.controlPower,
    this.cycle,
    this.cycleHistory = const [],
    this.lastCycleTime = Duration.zero,
    this.minCycleTime = Duration.zero,
    this.commandTimings = const [],
    this.machineState,
    this.reworkCount = 0,
    this.decision,
    this.config = const [],
    this.step,
    this.stepStats = const [],
    this.commands = const [],
    this.nameplate,
    this.running = false,
    this.stopPending = false,
    this.runStyle = RunStyle.continuous,
    this.supportedModes = const [],
    this.supportedRunStyles = const [RunStyle.continuous],
    this.modePolicy = const {},
    this.oee,
    this.alarmMeta = const [],
  });

  bool get isUnit => type == ModuleType.unit;

  /// Highest ACTIVE severity on THIS node (null = none).
  Severity? get ownSeverity {
    Severity? top;
    for (final e in activeEvents) {
      if (e.state == AlarmState.closed) continue;
      if (top == null || e.severity.index > top.index) top = e.severity;
    }
    // a module fault without an own log entry still shows as error via Status
    if (faultActive && (top == null || top.index < Severity.high.index)) {
      top = Severity.high;
    }
    return top;
  }

  /// Core 3.13 event-path highlight: max severity in this node's subtree.
  /// Every ancestor of an event source therefore tints (high > medium > low).
  Severity? get effectiveSeverity {
    Severity? top = ownSeverity;
    for (final c in children) {
      final cs = c.effectiveSeverity;
      if (cs != null && (top == null || cs.index > top.index)) top = cs;
    }
    return top;
  }

  ModuleNode? find(String p) {
    if (p == path) return this;
    for (final c in children) {
      final hit = c.find(p);
      if (hit != null) return hit;
    }
    return null;
  }
}
