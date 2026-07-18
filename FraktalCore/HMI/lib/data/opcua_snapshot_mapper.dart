library;

import '../domain/fieldbus.dart';
import '../domain/module_node.dart';
import '../domain/types.dart';

class OpcUaProjection {
  final List<ModuleNode> forest;
  final List<BusNode> fieldbus;
  final Map<String, String> browsePathByModulePath;
  final List<String> discardedAliases;

  const OpcUaProjection({
    required this.forest,
    required this.fieldbus,
    required this.browsePathByModulePath,
    this.discardedAliases = const [],
  });
}

/// Maps a transport-neutral flat OPC UA browse snapshot into the domain model.
/// The mapper keys off the normative Status member, never a concrete FB type.
class OpcUaSnapshotMapper {
  OpcUaProjection map(Map<String, Object?> document) {
    final rawValues = document['values'];
    if (rawValues is! Map) {
      throw const FormatException('OPC UA snapshot has no values object.');
    }
    final values = <String, Object?>{
      for (final entry in rawValues.entries) '${entry.key}': entry.value,
    };
    final candidatesByIdentity = <String, _ModuleCandidate>{};
    final discardedAliases = <String>[];
    for (final entry in values.entries) {
      if (!entry.key.endsWith('/Status/Name') || entry.value is! String) {
        continue;
      }
      final base =
          entry.key.substring(0, entry.key.length - '/Status/Name'.length);
      final type = _integer(values['$base/Status/ModuleType']);
      if (type <= ModuleType.none.index || type >= ModuleType.values.length) {
        continue;
      }
      final identity = entry.value as String;
      final browseName = base.substring(base.lastIndexOf('/') + 1);
      final localName = identity.substring(identity.lastIndexOf('.') + 1);
      // TF6100 can expose REFERENCE TO aliases whose Status still describes
      // the referenced module. Nested Status.Name is the full Fraktal path, so
      // compare its final segment with the local OPC UA browse name.
      if (browseName != localName) {
        discardedAliases.add('$base -> $identity');
        continue;
      }
      final candidate =
          _ModuleCandidate(base, identity, localName, ModuleType.values[type]);
      final existing = candidatesByIdentity[identity];
      if (existing == null) {
        candidatesByIdentity[identity] = candidate;
      } else {
        final preferred = _preferCanonical(existing, candidate);
        final alias = identical(preferred, existing) ? candidate : existing;
        candidatesByIdentity[identity] = preferred;
        discardedAliases.add('${alias.browsePath} -> $identity');
      }
    }

    for (final candidate in candidatesByIdentity.values) {
      final separator = candidate.identity.lastIndexOf('.');
      if (separator < 0) continue;
      final parentIdentity = candidate.identity.substring(0, separator);
      candidate.parent = candidatesByIdentity[parentIdentity];
      candidate.parent?.children.add(candidate);
    }

    final browseByModule = <String, String>{};
    ModuleNode project(_ModuleCandidate candidate) {
      final path = candidate.identity;
      browseByModule[path] = candidate.browsePath;
      final base = candidate.browsePath;
      final state = _enumAt(ExecState.values,
          _integer(values['$base/Status/State']), ExecState.ready);
      final isUnit = candidate.type == ModuleType.unit;
      final modeValue =
          _integer(values['$base/ModeActivePublished'], fallback: -1);
      final runStyleValue = _integer(values['$base/RunStyle'], fallback: 0);
      final currentMode = modeValue >= 0 && modeValue < UnitMode.values.length
          ? UnitMode.values[modeValue]
          : null;
      final accessLevel = _enumAt(AccessLevel.values,
          _integer(values['$base/Access/CurrentLevel']), AccessLevel.none);
      final required = <AccessLevel>[];
      for (var i = 0; i < GatedAction.values.length; i++) {
        final raw = _arrayElement(values, '$base/Access/Policy/Required', i);
        required
            .add(_enumAt(AccessLevel.values, _integer(raw), AccessLevel.admin));
      }
      final commandCount = _integer(values['$base/CatalogCount']);
      final commands = <CommandInfo>[];
      for (var i = 1; i <= commandCount; i++) {
        final prefix = _indexedPrefix(values, '$base/Catalog', i);
        if (prefix == null) continue;
        commands.add(CommandInfo(
          _integer(values['$prefix/Value']),
          _string(values['$prefix/Label']),
        ));
      }
      final children = candidate.children.map(project).toList()
        ..sort((a, b) => a.name.compareTo(b.name));
      final supportedModes = isUnit
          ? [
              for (var i = 0; i < UnitMode.values.length; i++)
                if (_arrayElement(values, '$base/SupportedModesPublished', i) ==
                    true)
                  UnitMode.values[i],
            ]
          : const <UnitMode>[];
      final supportedRunStyles = isUnit
          ? [
              for (var i = 0; i < RunStyle.values.length; i++)
                if (_arrayElement(
                        values, '$base/SupportedRunStylesPublished', i) ==
                    true)
                  RunStyle.values[i],
            ]
          : const <RunStyle>[];
      final modePolicy = <UnitMode, ModePolicy>{};
      if (isUnit) {
        for (var i = 0; i < UnitMode.values.length; i++) {
          final prefix = _indexedPrefix(values, '$base/ModePolicy', i + 1);
          if (prefix == null) continue;
          modePolicy[UnitMode.values[i]] = ModePolicy(
            _enumAt(ModeSwitchShield.values, _integer(values['$prefix/Shield']),
                ModeSwitchShield.confirm),
            _enumAt(ModeSwitchStyle.values, _integer(values['$prefix/Style']),
                ModeSwitchStyle.graceful),
          );
        }
      }

      final availableModels = <String>[];
      final availableModelCount = _integer(values['$base/AvailableModelCount']);
      for (var i = 1; i <= availableModelCount; i++) {
        final prefix = _indexedPrefix(values, '$base/AvailableModels', i);
        if (prefix == null) continue;
        final code = _string(values['$prefix/ModelCode']);
        if (code.isNotEmpty) availableModels.add(code);
      }

      final stepNo = _integer(values['$base/CurrentStep/StepNo']);
      StepInfo? step;
      if (isUnit && stepNo != 0) {
        final conds = <CondInfo>[];
        for (var i = 1; i <= 8; i++) {
          final prefix = _indexedPrefix(values, '$base/CurrentStep/Conds', i);
          if (prefix == null) continue;
          final label = _string(values['$prefix/Label']);
          if (label.isNotEmpty) {
            conds.add(CondInfo(label, _boolean(values['$prefix/Ok'])));
          }
        }
        step = StepInfo(
          stepNo: stepNo,
          stepName: _string(values['$base/CurrentStep/StepName']),
          awaitingLabel: _string(values['$base/CurrentStep/AwaitingLabel']),
          timeClass: _enumAt(TimeClass.values,
              _integer(values['$base/CurrentStep/Class']), TimeClass.work),
          expected: _duration(values['$base/CurrentStep/ExpectedTime']),
          conds: conds,
          starved: _boolean(values['$base/Starved']),
          blocked: _boolean(values['$base/Blocked']),
        );
      }

      // §8.11.4 — cycle profile, trend ring, throughput markers (Units)
      CycleProfile? cycle;
      final cycleHistory = <CycleSummary>[];
      var lastCycleTime = Duration.zero;
      var minCycleTime = Duration.zero;
      MachineState? machineState;
      if (isUnit) {
        final profileBase = '$base/Profiler/LastCycle';
        final cycleNo = _integer(values['$profileBase/CycleNo']);
        if (cycleNo > 0) {
          final steps = <StepTiming>[];
          final nSteps = _integer(values['$profileBase/NSteps']);
          for (var i = 1; i <= nSteps; i++) {
            final prefix = _indexedPrefix(values, '$profileBase/Steps', i);
            if (prefix == null) continue;
            steps.add(StepTiming(
              _integer(values['$prefix/StepNo']),
              _string(values['$prefix/StepName']),
              _enumAt(TimeClass.values, _integer(values['$prefix/Class']),
                  TimeClass.work),
              _duration(values['$prefix/Duration']),
              _duration(values['$prefix/Expected']),
            ));
          }
          cycle = CycleProfile(
            cycleNo: cycleNo,
            total: _duration(values['$profileBase/Total']),
            workTime: _duration(values['$profileBase/WorkTime']),
            waitTime: _duration(values['$profileBase/WaitTime']),
            steps: steps,
          );
        }
        lastCycleTime = _duration(values['$base/Profiler/LastCycleTime']);
        minCycleTime = _duration(values['$base/Profiler/MinCycleTime']);
        final head = _integer(values['$base/Profiler/HistoryHead']);
        if (head > 0) {
          // ring -> chronological list, oldest..newest, skipping empty slots
          const ringSize = 60; // PL_Fraktal.MAX_CYCLE_HISTORY
          for (var offset = ringSize; offset >= 1; offset--) {
            final index = ((head - 1 + offset) % ringSize) + 1;
            final prefix =
                _indexedPrefix(values, '$base/Profiler/History', index);
            if (prefix == null) continue;
            if (_integer(values['$prefix/CycleNo']) == 0) continue;
            cycleHistory.add(CycleSummary(
              cycleNo: _integer(values['$prefix/CycleNo']),
              total: _duration(values['$prefix/Total']),
              workTime: _duration(values['$prefix/WorkTime']),
              waitTime: _duration(values['$prefix/WaitTime']),
              byClass: [
                for (var c = 0; c < TimeClass.values.length; c++)
                  _duration(_arrayElement(values, '$prefix/ByClass', c)),
              ],
            ));
          }
        }
        final machineStateValue =
            _integer(values['$base/MachineState'], fallback: -1);
        machineState = machineStateValue >= 0 &&
                machineStateValue < MachineState.values.length
            ? MachineState.values[machineStateValue]
            : null;
      }
      final stepStats = <StepStat>[];
      if (isUnit) {
        for (var i = 1; i <= 32; i++) {
          final prefix = _indexedPrefix(values, '$base/Profiler/StepStats', i);
          if (prefix == null) continue;
          if (_integer(values['$prefix/Count']) == 0) continue;
          stepStats.add(StepStat(
            _integer(values['$prefix/Id']),
            _string(values['$prefix/Label']),
            _enumAt(TimeClass.values, _integer(values['$prefix/Class']),
                TimeClass.work),
            _duration(values['$prefix/Avg']),
            _duration(values['$prefix/Maximum']),
          ));
        }
      }
      // §8.11.4(a) — module command timing (any tier that ran commands)
      final commandTimings = <CommandTiming>[];
      for (var i = 1; i <= 8; i++) {
        final prefix = _indexedPrefix(values, '$base/Timing/Rows', i);
        if (prefix == null) continue;
        if (_integer(values['$prefix/Count']) == 0) continue;
        commandTimings.add(CommandTiming(
          _integer(values['$prefix/Id']),
          _string(values['$prefix/Label']),
          _integer(values['$prefix/Count']),
          _duration(values['$prefix/Last']),
          _duration(values['$prefix/Minimum']),
          _duration(values['$prefix/Maximum']),
          _duration(values['$prefix/Avg']),
        ));
      }

      DecisionRequest? decision;
      final prompt = _string(values['$base/Decision/Prompt']);
      if (isUnit && prompt.isNotEmpty) {
        final options = <String>[];
        for (var i = 0; i < 6; i++) {
          final option =
              _string(_arrayElement(values, '$base/Decision/Options', i));
          if (option.isNotEmpty) options.add(option);
        }
        final plcDefault = _integer(values['$base/Decision/Default']);
        decision = DecisionRequest(
          prompt: prompt,
          options: options,
          defaultOption: plcDefault > 0 ? plcDefault - 1 : -1,
        );
      }

      return ModuleNode(
        path: path,
        name: candidate.name,
        displayNameKey: _string(values['$base/Status/DisplayNameKey']),
        descriptionKey: _string(values['$base/Status/DescriptionKey']),
        type: candidate.type,
        state: state,
        faultActive: _boolean(values['$base/Status/FaultActive']),
        message: _string(values['$base/Status/Diagnostic/Description']),
        diagnosticIoTag: _string(values['$base/Status/Diagnostic/IoTag']),
        diagnosticIoAddress:
            _string(values['$base/Status/Diagnostic/IoAddress']),
        tileEnable: _boolean(values['$base/Status/TileEnable'], fallback: true),
        controlDomainId: _string(values['$base/Status/ControlDomainId']),
        children: children,
        modelCode: _string(values['$base/Model/ModelCode']),
        availableModels: availableModels,
        modeActive: isUnit ? currentMode : null,
        goodCount: _integer(values['$base/GoodCount']),
        nokCount: _integer(values['$base/NokCount']),
        reworkCount: _integer(values['$base/ReworkCount']),
        cycle: cycle,
        cycleHistory: cycleHistory,
        lastCycleTime: lastCycleTime,
        minCycleTime: minCycleTime,
        stepStats: stepStats,
        commandTimings: commandTimings,
        machineState: machineState,
        blocking: _boolean(values['$base/AlarmLog/Blocking']),
        access: isUnit
            ? AccessSession(
                level: accessLevel,
                user: _string(values['$base/Access/CurrentUser']),
                loginFailed: _boolean(values['$base/Access/LoginFailed']),
                required: required,
              )
            : null,
        commands: commands,
        decision: decision,
        step: step,
        running: _boolean(values['$base/RunningPublished'],
            fallback: state == ExecState.busy),
        stopPending: _boolean(values['$base/StopPendingPublished']),
        runStyle: _enumAt(RunStyle.values, runStyleValue, RunStyle.continuous),
        supportedModes: supportedModes.isEmpty && currentMode != null
            ? [currentMode]
            : supportedModes,
        supportedRunStyles: supportedRunStyles.isEmpty
            ? const [RunStyle.continuous]
            : supportedRunStyles,
        modePolicy: modePolicy,
      );
    }

    final roots = candidatesByIdentity.values
        .where((candidate) =>
            candidate.parent == null &&
            !candidate.identity.contains('.') &&
            candidate.type == ModuleType.unit)
        .map((candidate) => project(candidate))
        .toList()
      ..sort((a, b) => a.name.compareTo(b.name));

    return OpcUaProjection(
      forest: roots,
      fieldbus: _mapFieldbus(values),
      browsePathByModulePath: browseByModule,
      discardedAliases: discardedAliases,
    );
  }

  List<BusNode> _mapFieldbus(Map<String, Object?> values) {
    String? topology;
    for (final key in values.keys) {
      if (key.endsWith('/Topology/NodeCount')) {
        topology = key.substring(0, key.length - '/NodeCount'.length);
        break;
      }
    }
    if (topology == null) return const [];
    final count = _integer(values['$topology/NodeCount']);
    final nodes = <int, _BusCandidate>{};
    for (var index = 1; index <= count; index++) {
      final prefix = _indexedPrefix(values, '$topology/Nodes', index);
      if (prefix == null) continue;
      final channels = <IoChannel>[];
      final channelCount = _integer(values['$prefix/ChannelCount']);
      for (var channelIndex = 1; channelIndex <= channelCount; channelIndex++) {
        final channelPrefix =
            _indexedPrefix(values, '$prefix/Channels', channelIndex);
        if (channelPrefix == null) continue;
        channels.add(IoChannel(
          name: _string(values['$channelPrefix/Name']),
          descriptionKey: _string(values['$channelPrefix/DescriptionKey']),
          address: _string(values['$channelPrefix/Address']),
          path: _string(values['$channelPrefix/Path']),
          modulePath: _string(values['$channelPrefix/ModulePath']),
          dir: _enumAt(ChannelDir.values,
              _integer(values['$channelPrefix/Dir']), ChannelDir.input),
          kind: _enumAt(ChannelKind.values,
              _integer(values['$channelPrefix/Kind']), ChannelKind.digital),
          boolValue: _boolean(values['$channelPrefix/BoolValue']),
          analogValue: _number(values['$channelPrefix/AnalogValue']),
          unit: _string(values['$channelPrefix/Unit']),
          forced: _boolean(values['$channelPrefix/Forced']),
          quality: _boolean(values['$channelPrefix/Quality'], fallback: true),
          faultActive: _boolean(values['$channelPrefix/FaultActive']),
          diagnosticKey: _string(values['$channelPrefix/Diagnostic']),
        ));
      }
      nodes[index] = _BusCandidate(
        parent: _integer(values['$prefix/ParentIdx']),
        node: BusNode(
          name: _string(values['$prefix/Name']),
          descriptionKey: _string(values['$prefix/DescriptionKey']),
          typeId: _string(values['$prefix/TypeId']),
          address: _string(values['$prefix/Address']),
          state: _enumAt(NodeState.values, _integer(values['$prefix/State']),
              NodeState.offline),
          linkOk: _boolean(values['$prefix/LinkOk']),
          mappingValid:
              _boolean(values['$topology/MappingValid'], fallback: true),
          mappingDiagnosticKey: _string(values['$topology/MappingDiagnostic']),
          channels: channels,
        ),
      );
    }

    BusNode build(int index) {
      final candidate = nodes[index]!;
      final childNodes = nodes.entries
          .where((entry) => entry.value.parent == index)
          .map((entry) => build(entry.key))
          .toList();
      final source = candidate.node;
      return BusNode(
        name: source.name,
        descriptionKey: source.descriptionKey,
        typeId: source.typeId,
        address: source.address,
        state: source.state,
        linkOk: source.linkOk,
        mappingValid: source.mappingValid,
        mappingDiagnosticKey: source.mappingDiagnosticKey,
        channels: source.channels,
        children: childNodes,
      );
    }

    return nodes.entries
        .where((entry) => entry.value.parent == 0)
        .map((entry) => build(entry.key))
        .toList();
  }
}

class _ModuleCandidate {
  final String browsePath;
  final String identity;
  final String name;
  final ModuleType type;
  _ModuleCandidate? parent;
  final List<_ModuleCandidate> children = [];

  _ModuleCandidate(this.browsePath, this.identity, this.name, this.type);
}

_ModuleCandidate _preferCanonical(
    _ModuleCandidate left, _ModuleCandidate right) {
  final leftDepth = '/'.allMatches(left.browsePath).length;
  final rightDepth = '/'.allMatches(right.browsePath).length;
  if (leftDepth != rightDepth) return leftDepth < rightDepth ? left : right;
  return left.browsePath.compareTo(right.browsePath) <= 0 ? left : right;
}

class _BusCandidate {
  final int parent;
  final BusNode node;
  const _BusCandidate({required this.parent, required this.node});
}

String _string(Object? value) => value is String ? value : '';
bool _boolean(Object? value, {bool fallback = false}) =>
    value is bool ? value : fallback;
int _integer(Object? value, {int fallback = 0}) =>
    value is num ? value.toInt() : fallback;
double _number(Object? value) => value is num ? value.toDouble() : 0;
Duration _duration(Object? value) =>
    Duration(milliseconds: _number(value).round());

T _enumAt<T>(List<T> values, int index, T fallback) =>
    index >= 0 && index < values.length ? values[index] : fallback;

Object? _arrayElement(
    Map<String, Object?> values, String base, int zeroBasedIndex) {
  final direct = values[base];
  if (direct is List && zeroBasedIndex < direct.length) {
    return direct[zeroBasedIndex];
  }
  final zeroBased =
      values.containsKey('$base/0') || values.containsKey('$base[0]');
  final index = zeroBased ? zeroBasedIndex : zeroBasedIndex + 1;
  return values['$base/$index'] ?? values['$base[$index]'];
}

String? _indexedPrefix(
    Map<String, Object?> values, String base, int oneBasedIndex) {
  final zeroBased = values.keys
      .any((key) => key.startsWith('$base/0/') || key.startsWith('$base[0]/'));
  final index = zeroBased ? oneBasedIndex - 1 : oneBasedIndex;
  final alternatives = [
    '$base/$index',
    '$base[$index]',
  ];
  for (final alternative in alternatives) {
    if (values.keys.any((key) => key.startsWith('$alternative/'))) {
      return alternative;
    }
  }
  return null;
}
