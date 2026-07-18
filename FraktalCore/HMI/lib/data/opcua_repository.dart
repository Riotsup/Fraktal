library;

import 'dart:async';
import 'package:flutter/foundation.dart';
import '../domain/fieldbus.dart';
import '../domain/module_node.dart';
import '../domain/types.dart';
import 'opcua_session_client.dart';
import 'opcua_snapshot_mapper.dart';
import 'plc_repository.dart';

enum _HmiRequestKind {
  none,
  login,
  logout,
  setMode,
  setModel,
  start,
  stop,
  controlOn,
  controlOff,
  operatorReset,
  decisionAnswer,
  manualCommand,
  setRunStyle,
  stepRequest,
  setHoldRun,
  releaseStart,
  releaseManual,
  releaseAction,
  resetOee,
  writeConfig,
  shelveAlarm,
  unshelveAlarm,
  forceChannel,
}

/// Direct native OPC UA repository for Dart-native Flutter platforms. The
/// client browses the Fraktal contract generically; no module type or station
/// screen is compiled into this adapter.
class OpcUaRepository implements PlcRepository {
  final OpcUaSessionClient _client;
  final OpcUaSnapshotMapper _mapper;
  final Duration refreshInterval;
  final _forestController = StreamController<List<ModuleNode>>.broadcast();
  final _fieldbusController = StreamController<List<BusNode>>.broadcast();
  final _linkController = StreamController<LinkState>.broadcast();
  Timer? _timer;
  Future<void>? _refreshInFlight;
  bool _disposed = false;
  int _requestSequence = 0;
  DateTime _lastGood = DateTime.now();
  LinkState _link = LinkState.connecting;
  OpcUaProjection _projection = const OpcUaProjection(
      forest: [], fieldbus: [], browsePathByModulePath: {});
  Map<String, Object?> _values = const {};
  String _rootChildren = '';
  String _namespaceUris = '';
  String _aliasSignature = '';
  Future<void> _requestQueue = Future<void>.value();

  OpcUaRepository._(this._client, this._mapper, this.refreshInterval);

  static Future<OpcUaRepository> connectWithClient(
    OpcUaSessionClient client, {
    Duration refreshInterval = const Duration(milliseconds: 500),
  }) async {
    final repository =
        OpcUaRepository._(client, OpcUaSnapshotMapper(), refreshInterval);
    try {
      await repository._refresh();
      if (repository._projection.forest.isEmpty) {
        final keys = repository._values.keys.take(8).join(', ');
        final onlyStandardServer = repository._values.isEmpty &&
            repository._rootChildren == '0:Server(Object)';
        final plcNamespaceLoaded = repository._namespaceUris
            .contains('urn:BeckhoffAutomation:Ua:PLC1');
        final accessFiltered = onlyStandardServer && plcNamespaceLoaded;
        throw StateError('The OPC UA server is reachable, but no Fraktal root '
            'Unit was discovered. '
            '${accessFiltered ? 'TF6100 reports that the PLC1 Data Access namespace is loaded, but the current OPC UA identity cannot browse it. Assign this identity to a TF6100 group/role with recursive browse/read access to PLC1; grant write only to the HmiRequest command mailbox. ' : 'For TF6100 TMC-Filtered publication, verify ${onlyStandardServer ? 'that this OPC UA identity has browse/read access to the configured PLC Data Access namespace, ' : ''}that the root Unit instance has the OPC.UA.DA publication attribute and that the updated Port_<ADS port>.tmc was downloaded and reloaded. '}'
            'The root must publish Status : ST_ModuleStatus. '
            'Snapshot contained ${repository._values.length} value nodes'
            '${keys.isEmpty ? '' : '; first browse paths: $keys'}. '
            'Objects folder children: '
            '${repository._rootChildren.isEmpty ? '(none)' : repository._rootChildren}. '
            'Server namespaces: '
            '${repository._namespaceUris.isEmpty ? '(unavailable)' : repository._namespaceUris}.');
      }
      repository._timer =
          Timer.periodic(refreshInterval, (_) => repository._refresh());
      return repository;
    } on Object {
      await client.close();
      rethrow;
    }
  }

  Future<void> _refresh() {
    if (_disposed) return Future<void>.value();
    final active = _refreshInFlight;
    if (active != null) return active;
    final refresh = _performRefresh();
    _refreshInFlight = refresh;
    return refresh.whenComplete(() {
      if (identical(_refreshInFlight, refresh)) _refreshInFlight = null;
    });
  }

  Future<void> _performRefresh() async {
    try {
      final document = await _client.snapshot();
      final raw = document['values'];
      if (raw is! Map) throw const FormatException('Snapshot values missing.');
      _values = {for (final entry in raw.entries) '${entry.key}': entry.value};
      final root = document['rootChildren'];
      _rootChildren = root is List ? root.join(', ') : '';
      final namespaces = document['namespaces'];
      _namespaceUris = namespaces is List ? namespaces.join(', ') : '';
      _projection = _mapper.map(document);
      final aliases = _projection.discardedAliases;
      final aliasSignature = aliases.join('|');
      if (aliases.isNotEmpty && aliasSignature != _aliasSignature) {
        debugPrint('[Fraktal/Connection] stage=opcua-aliases-discarded '
            'count=${aliases.length} paths=${aliases.take(12).join(', ')}');
      }
      _aliasSignature = aliasSignature;
      _lastGood = DateTime.now();
      _setLink(LinkState.live);
      _forestController.add(_projection.forest);
      _fieldbusController.add(_projection.fieldbus);
    } on Object catch (error) {
      final age = DateTime.now().difference(_lastGood);
      _setLink(
          age >= const Duration(seconds: 5) ? LinkState.down : LinkState.stale);
      debugPrint(
          '[Fraktal/Connection] stage=opcua-refresh-failed error=$error');
    }
  }

  void _setLink(LinkState value) {
    if (_link == value) return;
    _link = value;
    _linkController.add(value);
  }

  @override
  Stream<List<ModuleNode>> forest() async* {
    yield _projection.forest;
    yield* _forestController.stream;
  }

  @override
  Stream<List<BusNode>> fieldbus() async* {
    yield _projection.fieldbus;
    yield* _fieldbusController.stream;
  }

  @override
  Stream<LinkState> linkState() async* {
    yield _link;
    yield* _linkController.stream;
  }

  String? _browseBase(String modulePath) =>
      _projection.browsePathByModulePath[modulePath];

  Future<bool> _write(String path, OpcUaWriteType type, Object value) async {
    if (_link != LinkState.live) return false;
    try {
      final written = await _client.write(path, type, value);
      if (!written) {
        debugPrint('[Fraktal/Connection] stage=opcua-write-refused path=$path');
      }
      return written;
    } on Object catch (error) {
      debugPrint('[Fraktal/Connection] stage=opcua-write-failed '
          'path=$path error=$error');
      return false;
    }
  }

  Future<bool> _request(
    String unitPath,
    _HmiRequestKind kind, {
    String targetPath = '',
    String nameValue = '',
    String textValue = '',
    String user = '',
    String secret = '',
    int intValue = 0,
    bool boolValue = false,
    int durationMs = 0,
  }) {
    final result = Completer<bool>();
    _requestQueue = _requestQueue.then((_) async {
      try {
        result.complete(await _performRequest(
          unitPath,
          kind,
          targetPath: targetPath,
          nameValue: nameValue,
          textValue: textValue,
          user: user,
          secret: secret,
          intValue: intValue,
          boolValue: boolValue,
          durationMs: durationMs,
        ));
      } on Object catch (error, stackTrace) {
        result.completeError(error, stackTrace);
      }
    });
    return result.future;
  }

  Future<bool> _performRequest(
    String unitPath,
    _HmiRequestKind kind, {
    required String targetPath,
    required String nameValue,
    required String textValue,
    required String user,
    required String secret,
    required int intValue,
    required bool boolValue,
    required int durationMs,
  }) async {
    final base = _browseBase(unitPath);
    if (base == null || _link != LinkState.live) {
      debugPrint('[Fraktal/Connection] stage=opcua-request-unavailable '
          'kind=${kind.name} unit=$unitPath link=${_link.name}');
      return false;
    }
    final request = '$base/HmiRequest';
    final sequence = _requestSequence = (_requestSequence + 1) & 0xffffffff;
    debugPrint('[Fraktal/Connection] stage=opcua-request-start '
        'kind=${kind.name} unit=$unitPath sequence=$sequence');
    final fields = <(String, OpcUaWriteType, Object)>[
      ('$request/Kind', OpcUaWriteType.int32, kind.index),
      ('$request/TargetPath', OpcUaWriteType.string, targetPath),
      ('$request/NameValue', OpcUaWriteType.string, nameValue),
      ('$request/TextValue', OpcUaWriteType.string, textValue),
      ('$request/User', OpcUaWriteType.string, user),
      ('$request/Secret', OpcUaWriteType.string, secret),
      ('$request/IntValue', OpcUaWriteType.int32, intValue),
      ('$request/BoolValue', OpcUaWriteType.boolean, boolValue),
      ('$request/DurationMs', OpcUaWriteType.uint32, durationMs),
    ];
    for (final field in fields) {
      if (!await _write(field.$1, field.$2, field.$3)) {
        debugPrint('[Fraktal/Connection] stage=opcua-request-write-failed '
            'kind=${kind.name} field=${field.$1} sequence=$sequence');
        return false;
      }
    }
    // Sequence is the commit marker and is deliberately written last.
    if (!await _write('$request/Sequence', OpcUaWriteType.uint32, sequence)) {
      debugPrint('[Fraktal/Connection] stage=opcua-request-commit-failed '
          'kind=${kind.name} sequence=$sequence');
      return false;
    }

    final deadline = DateTime.now().add(const Duration(seconds: 2));
    while (DateTime.now().isBefore(deadline) && _link == LinkState.live) {
      await _refresh();
      final ack = _integer(_values['$base/HmiResponse/AckSequence']);
      if (ack == sequence) {
        final accepted = _values['$base/HmiResponse/Accepted'] == true;
        final diagnostic = '${_values['$base/HmiResponse/Diagnostic'] ?? ''}';
        debugPrint('[Fraktal/Connection] stage=opcua-request-ack '
            'kind=${kind.name} sequence=$sequence accepted=$accepted '
            'diagnostic=$diagnostic');
        await _write(
            '$request/Kind', OpcUaWriteType.int32, _HmiRequestKind.none.index);
        return accepted;
      }
      await Future<void>.delayed(const Duration(milliseconds: 30));
    }
    debugPrint('[Fraktal/Connection] stage=opcua-request-timeout '
        'kind=${kind.name} sequence=$sequence');
    return false;
  }

  @override
  Future<bool> login(String rootPath, String user, String secret) async {
    // A LOGIN mailbox acknowledgement means the PLC consumed the request; it
    // does not mean the access provider accepted the credentials. The access
    // manager publishes the authoritative outcome immediately afterward.
    final consumed = await _request(
      rootPath,
      _HmiRequestKind.login,
      user: user,
      secret: secret,
    );
    if (!consumed) return false;
    await Future<void>.delayed(const Duration(milliseconds: 30));
    await _refresh();
    final base = _browseBase(rootPath);
    if (base == null) return false;
    final failed = _values['$base/Access/LoginFailed'] == true;
    final level = _integer(_values['$base/Access/CurrentLevel']);
    final currentUser = '${_values['$base/Access/CurrentUser'] ?? ''}';
    final authenticated =
        !failed && level > AccessLevel.none.index && currentUser == user;
    debugPrint('[Fraktal/Connection] stage=opcua-login-result '
        'authenticated=$authenticated level=$level loginFailed=$failed');
    return authenticated;
  }

  @override
  Future<void> logout(String rootPath) async {
    await _request(rootPath, _HmiRequestKind.logout);
  }

  @override
  Future<bool> setMode(String unitPath, UnitMode mode) =>
      _request(unitPath, _HmiRequestKind.setMode, intValue: mode.index);

  @override
  Future<bool> setModel(String rootPath, String modelCode) =>
      _request(rootPath, _HmiRequestKind.setModel, textValue: modelCode);

  @override
  Future<bool> start(String unitPath) =>
      _request(unitPath, _HmiRequestKind.start);

  @override
  Future<bool> stop(String unitPath) =>
      _request(unitPath, _HmiRequestKind.stop);

  @override
  Future<bool> controlOn(String unitPath) =>
      _request(unitPath, _HmiRequestKind.controlOn);

  @override
  Future<bool> controlOff(String unitPath) =>
      _request(unitPath, _HmiRequestKind.controlOff);

  @override
  Future<bool> operatorReset(String unitPath) =>
      _request(unitPath, _HmiRequestKind.operatorReset);

  @override
  Future<void> setDecisionAnswer(String unitPath, int option) async {
    await _request(unitPath, _HmiRequestKind.decisionAnswer, intValue: option);
  }

  @override
  Future<bool> manualCommand(String unitPath, String targetPath, int value) =>
      _request(unitPath, _HmiRequestKind.manualCommand,
          targetPath: targetPath, intValue: value);

  @override
  Future<bool> setRunStyle(String unitPath, RunStyle style) =>
      _request(unitPath, _HmiRequestKind.setRunStyle, intValue: style.index);

  @override
  Future<void> stepRequest(String unitPath) async {
    await _request(unitPath, _HmiRequestKind.stepRequest);
  }

  @override
  Future<void> setHoldRun(String unitPath, bool held) async {
    await _request(unitPath, _HmiRequestKind.setHoldRun, boolValue: held);
  }

  @override
  Future<ReleaseReport> releaseReportStart(String unitPath) async {
    final accepted = await _request(unitPath, _HmiRequestKind.releaseStart);
    return _readReleaseReport(unitPath, accepted);
  }

  @override
  Future<ReleaseReport> releaseReportManual(
      String unitPath, String targetPath, int commandValue) async {
    final accepted = await _request(unitPath, _HmiRequestKind.releaseManual,
        targetPath: targetPath, intValue: commandValue);
    return _readReleaseReport(unitPath, accepted);
  }

  @override
  Future<ReleaseReport> releaseReportAction(
      String unitPath, GatedAction action) async {
    final accepted = await _request(unitPath, _HmiRequestKind.releaseAction,
        intValue: action.index);
    return _readReleaseReport(unitPath, accepted);
  }

  ReleaseReport _readReleaseReport(String unitPath, bool requestAccepted) {
    final base = _browseBase(unitPath);
    if (base == null || !requestAccepted) {
      return const ReleaseReport(false, [
        ReleaseReason('std.release.transportUnavailable', ReleaseKind.other),
      ]);
    }
    final response = '$base/HmiResponse/Report';
    final released = _values['$response/Released'] == true;
    final count = _integer(_values['$response/Count']);
    final reasons = <ReleaseReason>[];
    for (var i = 1; i <= count; i++) {
      final prefix = _indexedPrefix(_values, '$response/Reasons', i);
      if (prefix == null) continue;
      reasons.add(ReleaseReason(
        '${_values['$prefix/Description'] ?? ''}',
        _enumAt(ReleaseKind.values, _integer(_values['$prefix/Kind']),
            ReleaseKind.other),
        bypassable: _values['$prefix/Bypassable'] == true,
        reasonCode: _integer(_values['$prefix/ReasonCode']),
        sourcePath: '${_values['$prefix/SourcePath'] ?? ''}',
      ));
    }
    debugPrint('[Fraktal/Connection] stage=opcua-release-report '
        'unit=$unitPath released=$released count=$count '
        'mappedReasons=${reasons.length}');
    return ReleaseReport(released, reasons);
  }

  @override
  Future<bool> resetOee(String unitPath) =>
      _request(unitPath, _HmiRequestKind.resetOee);

  @override
  Future<bool> writeConfig(String nodePath, CfgField field, String value) =>
      _request(_owningRoot(nodePath), _HmiRequestKind.writeConfig,
          targetPath: nodePath, nameValue: field.name, textValue: value);

  @override
  Future<bool> shelveAlarm(String unitPath, String sourcePath,
          String description, Duration duration) =>
      _request(unitPath, _HmiRequestKind.shelveAlarm,
          targetPath: sourcePath,
          textValue: description,
          durationMs: duration.inMilliseconds);

  @override
  Future<bool> unshelveAlarm(
          String unitPath, String sourcePath, String description) =>
      _request(unitPath, _HmiRequestKind.unshelveAlarm,
          targetPath: sourcePath, textValue: description);

  @override
  Future<bool> forceChannel(String rootPath, String channelPath,
          {required bool force,
          bool boolValue = false,
          double analogValue = 0}) =>
      _request(rootPath, _HmiRequestKind.forceChannel,
          targetPath: channelPath,
          boolValue: force,
          textValue: boolValue ? 'true' : 'false',
          nameValue: '$analogValue');

  String _owningRoot(String path) {
    for (final root in _projection.forest) {
      if (path == root.path || path.startsWith('${root.path}.'))
        return root.path;
    }
    return path;
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _timer?.cancel();
    unawaited(_client.close());
    _forestController.close();
    _fieldbusController.close();
    _linkController.close();
  }
}

int _integer(Object? value) => value is num ? value.toInt() : -1;
T _enumAt<T>(List<T> values, int index, T fallback) =>
    index >= 0 && index < values.length ? values[index] : fallback;

String? _indexedPrefix(
    Map<String, Object?> values, String base, int oneBasedIndex) {
  for (final candidate in [
    '$base/$oneBasedIndex',
    '$base[$oneBasedIndex]',
    '$base/${oneBasedIndex - 1}',
    '$base[${oneBasedIndex - 1}]',
  ]) {
    if (values.keys.any((key) => key.startsWith('$candidate/')))
      return candidate;
  }
  return null;
}
