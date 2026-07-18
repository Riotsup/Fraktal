/// HMI-local root-Unit scope. This is defense in depth: the PLC still performs
/// access and release checks, while this adapter prevents a configured HMI from
/// reading or addressing roots outside its administrator-selected assignment.
library;

import 'dart:async';
import '../domain/fieldbus.dart';
import '../domain/module_node.dart';
import '../domain/types.dart';
import 'plc_repository.dart';

class ScopedPlcRepository implements PlcRepository {
  final PlcRepository source;
  final _forest = StreamController<List<ModuleNode>>.broadcast();
  final _fieldbus = StreamController<List<BusNode>>.broadcast();
  late final StreamSubscription<List<ModuleNode>> _forestSub;
  late final StreamSubscription<List<BusNode>> _fieldbusSub;
  List<ModuleNode> _availableRoots = const [];
  List<BusNode> _availableBus = const [];
  Set<String> _allowedRoots;
  bool _configured;

  ScopedPlcRepository(
    this.source, {
    Iterable<String> allowedRoots = const [],
    bool configured = false,
  })  : _allowedRoots = Set<String>.from(allowedRoots),
        _configured = configured {
    _forestSub = source.forest().listen((roots) {
      _availableRoots = roots;
      _publish();
    }, onError: _forest.addError);
    _fieldbusSub = source.fieldbus().listen((nodes) {
      _availableBus = nodes;
      _publishBus();
    }, onError: _fieldbus.addError);
  }

  List<ModuleNode> get availableRoots => List.unmodifiable(_availableRoots);

  void setScope(Iterable<String> rootPaths) {
    _allowedRoots = Set<String>.from(rootPaths);
    _configured = true;
    _publish();
    _publishBus();
  }

  void _publish() => _forest.add(_configured
      ? _availableRoots
          .where((root) => _allowedRoots.contains(root.path))
          .toList()
      : _availableRoots);

  void _publishBus() => _fieldbus.add(_configured
      ? _availableBus.map(_filterBusNode).whereType<BusNode>().toList()
      : _availableBus);

  BusNode? _filterBusNode(BusNode node) {
    final channels =
        node.channels.where((channel) => _allows(channel.path)).toList();
    final children =
        node.children.map(_filterBusNode).whereType<BusNode>().toList();
    if (channels.isEmpty && children.isEmpty) return null;
    return BusNode(
      name: node.name,
      descriptionKey: node.descriptionKey,
      typeId: node.typeId,
      address: node.address,
      state: node.state,
      linkOk: node.linkOk,
      mappingValid: node.mappingValid,
      mappingDiagnosticKey: node.mappingDiagnosticKey,
      channels: channels,
      children: children,
    );
  }

  bool _allows(String path) =>
      !_configured ||
      _allowedRoots.any((root) => path == root || path.startsWith('$root.'));

  Future<bool> _bool(String path, Future<bool> Function() action) =>
      _allows(path) ? action() : Future.value(false);
  Future<void> _void(String path, Future<void> Function() action) =>
      _allows(path) ? action() : Future.value();

  @override
  Stream<List<ModuleNode>> forest() {
    scheduleMicrotask(_publish);
    return _forest.stream;
  }

  @override
  Stream<LinkState> linkState() => source.linkState();
  @override
  Stream<List<BusNode>> fieldbus() {
    scheduleMicrotask(_publishBus);
    return _fieldbus.stream;
  }

  @override
  Future<bool> login(String rootPath, String user, String secret) =>
      _bool(rootPath, () => source.login(rootPath, user, secret));
  @override
  Future<void> logout(String rootPath) =>
      _void(rootPath, () => source.logout(rootPath));
  @override
  Future<bool> setMode(String unitPath, UnitMode mode) =>
      _bool(unitPath, () => source.setMode(unitPath, mode));
  @override
  Future<bool> setModel(String rootPath, String modelCode) =>
      _bool(rootPath, () => source.setModel(rootPath, modelCode));
  @override
  Future<bool> start(String unitPath) =>
      _bool(unitPath, () => source.start(unitPath));
  @override
  Future<bool> stop(String unitPath) =>
      _bool(unitPath, () => source.stop(unitPath));
  @override
  Future<bool> controlOn(String unitPath) =>
      _bool(unitPath, () => source.controlOn(unitPath));
  @override
  Future<bool> controlOff(String unitPath) =>
      _bool(unitPath, () => source.controlOff(unitPath));
  @override
  Future<bool> operatorReset(String unitPath) =>
      _bool(unitPath, () => source.operatorReset(unitPath));
  @override
  Future<void> setDecisionAnswer(String unitPath, int option) =>
      _void(unitPath, () => source.setDecisionAnswer(unitPath, option));
  @override
  Future<bool> manualCommand(String unitPath, String targetPath, int value) =>
      !_allows(unitPath) || !_allows(targetPath)
          ? Future.value(false)
          : source.manualCommand(unitPath, targetPath, value);
  @override
  Future<bool> setRunStyle(String unitPath, RunStyle style) =>
      _bool(unitPath, () => source.setRunStyle(unitPath, style));
  @override
  Future<void> stepRequest(String unitPath) =>
      _void(unitPath, () => source.stepRequest(unitPath));
  @override
  Future<void> setHoldRun(String unitPath, bool held) =>
      _void(unitPath, () => source.setHoldRun(unitPath, held));
  @override
  Future<ReleaseReport> releaseReportStart(String unitPath) => _allows(unitPath)
      ? source.releaseReportStart(unitPath)
      : Future.value(_outsideScope);
  @override
  Future<ReleaseReport> releaseReportManual(
          String unitPath, String targetPath, int commandValue) =>
      _allows(unitPath) && _allows(targetPath)
          ? source.releaseReportManual(unitPath, targetPath, commandValue)
          : Future.value(_outsideScope);
  @override
  Future<ReleaseReport> releaseReportAction(
          String unitPath, GatedAction action) =>
      _allows(unitPath)
          ? source.releaseReportAction(unitPath, action)
          : Future.value(_outsideScope);
  @override
  Future<bool> resetOee(String unitPath) =>
      _bool(unitPath, () => source.resetOee(unitPath));
  @override
  Future<bool> writeConfig(String nodePath, CfgField field, String value) =>
      _bool(nodePath, () => source.writeConfig(nodePath, field, value));
  @override
  Future<bool> shelveAlarm(String unitPath, String sourcePath,
          String description, Duration duration) =>
      !_allows(unitPath) || !_allows(sourcePath)
          ? Future.value(false)
          : source.shelveAlarm(unitPath, sourcePath, description, duration);
  @override
  Future<bool> unshelveAlarm(
          String unitPath, String sourcePath, String description) =>
      !_allows(unitPath) || !_allows(sourcePath)
          ? Future.value(false)
          : source.unshelveAlarm(unitPath, sourcePath, description);
  @override
  Future<bool> forceChannel(String rootPath, String channelPath,
          {required bool force,
          bool boolValue = false,
          double analogValue = 0}) =>
      _bool(
          rootPath,
          () => source.forceChannel(rootPath, channelPath,
              force: force, boolValue: boolValue, analogValue: analogValue));

  static const _outsideScope = ReleaseReport(false, [
    ReleaseReason('std.release.outsideAssignment', ReleaseKind.access),
  ]);

  @override
  void dispose() {
    _forestSub.cancel();
    _fieldbusSub.cancel();
    source.dispose();
    _forest.close();
    _fieldbus.close();
  }
}
