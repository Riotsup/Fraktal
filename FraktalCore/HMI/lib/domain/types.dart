/// PLC contract enums — ordinals MUST match the Fraktal Core DUTs exactly
/// (E_ExecState, E_ModuleType, E_Severity, E_AccessLevel, E_GatedAction,
/// E_ResetClass, E_AlarmState, E_Mode). The transport carries the DINT value;
/// these `index` positions are the contract (Core 3.10(a'), 8.8).
library;

enum ExecState { ready, busy, done, error, aborted }

enum ModuleType { none, unit, equipmentModule, controlModule }

enum Severity { low, medium, high } // E_Severity: LOW=0 MED=1 HIGH=2

enum ResetClass { autoReset, manualReset }

enum AlarmState { closed, active, waitReset }

enum AccessLevel { none, operator, technician, engineer, admin }

enum GatedAction {
  dataRead,
  dataWrite,
  manual,
  changeover,
  modeChange,
  startStop,
  alarmHistory,
  alarmReset,
  accessPolicy,
  alarmShelve, // §8.10 (ordinal 9, mirrors E_GatedAction.ALARM_SHELVE)
  powerControl, // §9.8 Control On/Off (append-only ordinal 10)
}

enum UnitMode {
  auto,
  manual,
  home,
  changeover,
  calibration,
  capability,
  adjustment
}

/// One §8.3 alarm/event (subset the HMI renders).
class AlarmEvent {
  final Severity severity;
  final String description;
  final String sourcePath;
  final ResetClass resetClass;
  final AlarmState state;
  final DateTime comeAt;
  final DateTime? goneAt;
  final Duration? duration; // filled on close
  final int
      reasonCode; // §8.8 (0 = none) — joins the §8.9 rationalization record
  final bool shelved; // §8.10 annunciation suppressed (control unaffected)
  final String ioTag; // untranslated schematic/electrical tag, when applicable
  final String ioAddress; // terminal/channel locator
  const AlarmEvent({
    required this.severity,
    required this.description,
    required this.sourcePath,
    required this.resetClass,
    required this.state,
    required this.comeAt,
    this.goneAt,
    this.duration,
    this.reasonCode = 0,
    this.shelved = false,
    this.ioTag = '',
    this.ioAddress = '',
  });
}

/// §7.7 session snapshot published per root.
class AccessSession {
  final AccessLevel level;
  final String user;
  final bool loginFailed;
  final List<AccessLevel> required; // index = GatedAction.index (11 entries)
  const AccessSession({
    this.level = AccessLevel.none,
    this.user = '',
    this.loginFailed = false,
    this.required = const [
      AccessLevel.none,
      AccessLevel.none,
      AccessLevel.none,
      AccessLevel.none,
      AccessLevel.none,
      AccessLevel.none,
      AccessLevel.none,
      AccessLevel.none,
      AccessLevel.none,
      AccessLevel.none,
      AccessLevel.none,
    ],
  });
  bool permits(GatedAction a) {
    // Fail closed if a stale transport publishes an older, shorter policy array.
    if (a.index >= required.length) return false;
    return level.index >= required[a.index].index;
  }
}

// ── Optional typed facets a module MAY publish (annex-specific data over the
//    same §3.10 self-description). The generic detail view renders whichever are
//    present — a station adds no HMI code. ────────────────────────────────────

/// Annex D — external device link supervision (I_DeviceConnector).
class LinkFacet {
  final bool linked;
  final DateTime? lastSeen;
  final String linkReason; // first-out when not linked
  const LinkFacet({this.linked = true, this.lastSeen, this.linkReason = ''});
}

enum SafetyDeviceKind {
  none,
  estop,
  guardDoor,
  lightCurtain,
  safetyScanner,
  safetyMat,
  enableSwitch,
  safetyValve,
  safeDrive,
  safetySensor,
  other,
  twoHandControl
}

enum SafetyState { unavailable, safeState, ready, demand, resetRequired, fault }

class SafetyDeviceStatus {
  final String name, description;
  final SafetyDeviceKind kind;
  final SafetyState state;
  final bool ready, demandActive, safeStateActive, resetRequired, faultActive;
  final bool mutingActive, bridgeActive, fieldbusHealthy;
  final int affectedPowerMask;
  const SafetyDeviceStatus(
      {required this.name,
      this.description = '',
      this.kind = SafetyDeviceKind.other,
      this.state = SafetyState.unavailable,
      this.ready = false,
      this.demandActive = false,
      this.safeStateActive = true,
      this.resetRequired = false,
      this.faultActive = false,
      this.mutingActive = false,
      this.bridgeActive = false,
      this.fieldbusHealthy = true,
      this.affectedPowerMask = 0});
}

class SafetyFacet {
  final bool allSafe, demandActive, resetRequired, faultActive;
  final bool mutingActive, bridgeActive, stopRequested;
  final List<SafetyDeviceStatus> devices;
  const SafetyFacet(
      {this.allSafe = true,
      this.demandActive = false,
      this.resetRequired = false,
      this.faultActive = false,
      this.mutingActive = false,
      this.bridgeActive = false,
      this.stopRequested = false,
      this.devices = const []});
}

enum PowerState { off, energizing, on, deenergizing, tripped, fault }

enum PowerGroupKind {
  control,
  valveZone,
  driveGroup,
  heater,
  processEnergy,
  auxiliary
}

enum FieldbusLossReaction { alarmOnly, stopUnit, powerGroupOff, controlOff }

class PowerGroupStatus {
  final String name, diagnostic;
  final PowerGroupKind kind;
  final PowerState state;
  final bool requiredForControl, requestedOn, powerOn, safetyPermit;
  final bool fieldbusHealthy, rearmRequired;
  final FieldbusLossReaction fieldbusLossReaction;
  const PowerGroupStatus(
      {required this.name,
      this.diagnostic = '',
      this.kind = PowerGroupKind.control,
      this.state = PowerState.off,
      this.requiredForControl = true,
      this.requestedOn = false,
      this.powerOn = false,
      this.safetyPermit = false,
      this.fieldbusHealthy = true,
      this.rearmRequired = false,
      this.fieldbusLossReaction = FieldbusLossReaction.controlOff});
}

class ControlPowerFacet {
  final bool requestedOn, controlOn, transitioning, rearmRequired;
  final String diagnostic;
  final List<PowerGroupStatus> groups;
  const ControlPowerFacet(
      {this.requestedOn = false,
      this.controlOn = false,
      this.transitioning = false,
      this.rearmRequired = false,
      this.diagnostic = '',
      this.groups = const []});
}

/// Annex E — one measured value with limits (ST_MeasRecord).
class MeasRecord {
  final String name;
  final double value, min, max, target;
  final String unit;
  final bool inTol;
  const MeasRecord(this.name, this.value, this.min, this.max, this.target,
      this.unit, this.inTol);
}

enum Verdict { none, ok, nok, rework }

/// Annex E — part context/result (ST_PartContext + ST_PartResult).
class PartFacet {
  final String uid;
  final bool present;
  final Verdict verdict;
  final String reason; // first NOK reason (§8.8 vocabulary)
  final List<MeasRecord> records;
  const PartFacet(
      {this.uid = '',
      this.present = false,
      this.verdict = Verdict.none,
      this.reason = '',
      this.records = const []});
}

/// Annex F — PackML state (ISA-TR88.00.02 / OPC 30050).
enum PackMLState {
  idle,
  starting,
  execute,
  completing,
  complete,
  held,
  holding,
  suspended,
  aborted,
  stopped,
  resetting
}

/// Annex G/I — motion/axis published status (PLCopen Motion / robot).
class MotionFacet {
  final double actualPosition, actualVelocity, targetPosition;
  final String unit;
  final bool moving, homed;
  const MotionFacet(
      {this.actualPosition = 0,
      this.actualVelocity = 0,
      this.targetPosition = 0,
      this.unit = 'mm',
      this.moving = false,
      this.homed = true});
}

/// §8.11.4 — one step of the cycle profile (waterfall row) with time class.
enum TimeClass {
  work,
  waitUpstream,
  waitDownstream,
  waitOperator,
  waitExternal
}

class StepTiming {
  final int stepNo;
  final String stepName;
  final TimeClass timeClass;
  final Duration duration;
  final Duration expected; // §8.11.4(c) declared guard (zero = none declared)
  const StepTiming(this.stepNo, this.stepName, this.timeClass, this.duration,
      [this.expected = Duration.zero]);
}

class CycleProfile {
  final int cycleNo;
  final Duration total, workTime, waitTime;
  final List<StepTiming> steps;
  const CycleProfile(
      {this.cycleNo = 0,
      this.total = Duration.zero,
      this.workTime = Duration.zero,
      this.waitTime = Duration.zero,
      this.steps = const []});
}

/// §8.11.4 one completed cycle's totals (Profiler.History ring) — the trend
/// source that explains WHY cycle time moved: work vs each wait class.
class CycleSummary {
  final int cycleNo;
  final Duration total, workTime, waitTime;
  final List<Duration> byClass; // indexed by TimeClass.index (5 entries)
  const CycleSummary(
      {this.cycleNo = 0,
      this.total = Duration.zero,
      this.workTime = Duration.zero,
      this.waitTime = Duration.zero,
      this.byClass = const []});
}

/// §8.11.4(a) one command-timing aggregate (module Timing.Rows[]) — the
/// drill-through from a slow step to the module command that consumed the time.
class CommandTiming {
  final int id;
  final String label;
  final int count;
  final Duration last, minimum, maximum, avg;
  const CommandTiming(this.id, this.label, this.count, this.last, this.minimum,
      this.maximum, this.avg);
}

/// §6.11 — operator decision request (ST_DecisionRequest).
class DecisionRequest {
  final String prompt;
  final List<String> options;
  final int defaultOption;
  const DecisionRequest(
      {this.prompt = '', this.options = const [], this.defaultOption = 0});
  bool get pending => prompt.isNotEmpty;
}

/// §3.8a — one editable persistent value (ParCfg or StationCfg field).
enum CfgKind { parCfg, stationCfg }

enum CfgType { number, text, boolean, time }

class CfgField {
  final String name;
  final String labelKey;
  final CfgKind kind;
  final CfgType type;
  final String value;
  final String unit;
  const CfgField(this.name, this.kind, this.type, this.value,
      {this.unit = '', this.labelKey = ''});
}

// ── Current step (§6.5/§6.9) and per-step aggregates (§8.11.4 Pareto) ──────────

class CondInfo {
  final String label;
  final bool ok;
  const CondInfo(this.label, this.ok);
}

class StepInfo {
  final int stepNo;
  final String stepName;
  final String awaitingLabel; // '' if not awaiting a module
  final TimeClass timeClass;
  final Duration expected;
  final List<CondInfo> conds; // named plain-condition waits (§6.9b)
  final bool starved, blocked;
  final bool steppable; // §3.4.2 per-step stop-point flag (default true)
  const StepInfo({
    this.stepNo = 0,
    this.stepName = '',
    this.awaitingLabel = '',
    this.timeClass = TimeClass.work,
    this.expected = Duration.zero,
    this.conds = const [],
    this.starved = false,
    this.blocked = false,
    this.steppable = true,
  });
  bool get active => stepNo != 0;
}

/// §8.11.3 — standardized machine state for OEE. Ordinals are the PLC
/// E_MachineState transport contract (append-only).
enum MachineState {
  producing,
  idle,
  blocked,
  starved,
  down,
  changeover,
  stopped,
}

/// §8.11.4 Profiler.StepStats[] — per-StepNo aggregate for the Pareto.
class StepStat {
  final int stepNo;
  final String label;
  final TimeClass timeClass;
  final Duration avg, max;
  const StepStat(this.stepNo, this.label, this.timeClass, this.avg, this.max);
}

/// Connection state to the PLC transport (HMI must always show liveness).
enum LinkState { connecting, live, stale, down }

/// §7.6.1 — one entry in a module's published manual-command catalog.
class CommandInfo {
  final int value;
  final String label;
  const CommandInfo(this.value, this.label);
}

/// §3.4.2 run style (HMI-selectable per mode).
enum RunStyle { continuous, singleStep, holdToRun }

/// §3.4.1 mode-switch shield/style (per-mode policy the HMI reads to decide prompts).
enum ModeSwitchShield { interruptible, confirm, blockedWhileRunning }

enum ModeSwitchStyle { graceful, immediate }

class ModePolicy {
  final ModeSwitchShield shield;
  final ModeSwitchStyle style;
  const ModePolicy(this.shield, this.style);
}

/// §7.8 release report — the full 'why is this blocked?' rollup
/// (one reason a gated action is currently withheld; rollup, not first-out).
enum ReleaseKind { mode, access, alarm, interlock, other }

class ReleaseReason {
  final String description;
  final ReleaseKind kind;
  final bool bypassable;
  final int reasonCode;
  final String sourcePath;
  const ReleaseReason(this.description, this.kind,
      {this.bypassable = false, this.reasonCode = 0, this.sourcePath = ''});
}

class ReleaseReport {
  final bool released;
  final List<ReleaseReason> reasons;
  const ReleaseReport(this.released, this.reasons);
  static const empty = ReleaseReport(true, []);
}

/// §3.10.1 digital nameplate — asset identity (IDTA 02006-aligned). Read-only.
class Nameplate {
  final String productUri, manufacturer, designation, serial, year;
  final String hwVersion, fwVersion, swVersion, orderCode, docUrl;
  const Nameplate({
    this.productUri = '',
    this.manufacturer = '',
    this.designation = '',
    this.serial = '',
    this.year = '',
    this.hwVersion = '',
    this.fwVersion = '',
    this.swVersion = '',
    this.orderCode = '',
    this.docUrl = '',
  });
  bool get isEmpty =>
      manufacturer.isEmpty && serial.isEmpty && designation.isEmpty;
}

/// §8.5.1 OEE snapshot: factors 0..1; an invalid factor is omitted from the
/// product and rendered as '—', never assumed 100%.
class OeeSnapshot {
  final double availability, performance, quality, oee;
  final bool availValid, perfValid, qualValid, oeeValid;
  final List<double> trend; // recent OEE samples, oldest..newest (sparkline)
  const OeeSnapshot({
    this.availability = 0,
    this.performance = 0,
    this.quality = 0,
    this.oee = 0,
    this.availValid = false,
    this.perfValid = false,
    this.qualValid = false,
    this.oeeValid = false,
    this.trend = const [],
  });
}

/// §8.9 rationalization record: what to DO about a reason, and shelvability.
class AlarmMeta {
  final int reasonCode;
  final String operatorAction;
  final String consequence;
  final bool shelvable;
  const AlarmMeta(this.reasonCode, this.operatorAction, this.consequence,
      {this.shelvable = false});
}
