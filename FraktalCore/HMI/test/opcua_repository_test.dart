import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:fraktal_hmi/data/opcua_repository.dart';
import 'package:fraktal_hmi/data/opcua_session_client.dart';
import 'package:fraktal_hmi/domain/types.dart';

void main() {
  test('mode request shares an in-flight refresh and reads its acknowledgement',
      () async {
    final client = _OverlappingRefreshClient();
    final repository = await OpcUaRepository.connectWithClient(
      client,
      refreshInterval: const Duration(milliseconds: 10),
    );
    addTearDown(repository.dispose);

    await client.refreshStarted.future.timeout(const Duration(seconds: 1));
    final request = repository.setMode('PneumaticPress', UnitMode.manual);
    await client.sequenceWritten.future.timeout(const Duration(seconds: 1));
    client.releaseRefresh.complete();

    expect(await request.timeout(const Duration(seconds: 1)), isTrue);
    expect(client.snapshotCalls, 2);
    expect(client.writes['PLC1/MAIN/PneumaticPress/HmiRequest/IntValue'],
        UnitMode.manual.index);
  });

  test('login returns the access-provider result, not mailbox consumption',
      () async {
    final rejectedClient = _LoginClient(loginSucceeds: false);
    final rejectedRepository = await OpcUaRepository.connectWithClient(
      rejectedClient,
      refreshInterval: const Duration(days: 1),
    );
    addTearDown(rejectedRepository.dispose);

    expect(
      await rejectedRepository.login('PneumaticPress', 'admin1', 'wrong'),
      isFalse,
    );
    expect(rejectedClient.sequence, 1);

    final acceptedClient = _LoginClient(loginSucceeds: true);
    final acceptedRepository = await OpcUaRepository.connectWithClient(
      acceptedClient,
      refreshInterval: const Duration(days: 1),
    );
    addTearDown(acceptedRepository.dispose);

    expect(
      await acceptedRepository.login('PneumaticPress', 'admin1', '2468'),
      isTrue,
    );
  });

  test('release query maps the complete native OPC UA reason report', () async {
    final client = _ReleaseClient();
    final repository = await OpcUaRepository.connectWithClient(
      client,
      refreshInterval: const Duration(days: 1),
    );
    addTearDown(repository.dispose);

    final report = await repository.releaseReportStart('PneumaticPress');

    expect(report.released, isFalse);
    expect(report.reasons, hasLength(2));
    expect(report.reasons[0].description, 'std.release.unitNotReady');
    expect(report.reasons[0].kind, ReleaseKind.mode);
    expect(report.reasons[0].sourcePath, 'PneumaticPress');
    expect(report.reasons[1].description, 'std.release.controlDomainNotReady');
    expect(report.reasons[1].kind, ReleaseKind.interlock);
    expect(report.reasons[1].reasonCode, 2002);
  });
}

class _OverlappingRefreshClient implements OpcUaSessionClient {
  final refreshStarted = Completer<void>();
  final releaseRefresh = Completer<void>();
  final sequenceWritten = Completer<void>();
  final Map<String, Object> writes = {};
  var snapshotCalls = 0;
  var sequence = 0;

  @override
  Future<Map<String, Object?>> snapshot() async {
    snapshotCalls++;
    if (snapshotCalls > 1) {
      if (!refreshStarted.isCompleted) refreshStarted.complete();
      await releaseRefresh.future;
    }
    const base = 'PLC1/MAIN/PneumaticPress';
    return {
      'protocol': 'fraktal.opcua.snapshot.v1',
      'nodeCount': 12,
      'truncated': false,
      'rootChildren': ['4:PLC1(Object)'],
      'namespaces': [
        'http://opcfoundation.org/UA/',
        'urn:BeckhoffAutomation:Ua:PLC1',
      ],
      'values': {
        '$base/Status/Name': 'PneumaticPress',
        '$base/Status/ModuleType': ModuleType.unit.index,
        '$base/Status/State': ExecState.ready.index,
        '$base/ModeActivePublished':
            sequence == 0 ? UnitMode.auto.index : UnitMode.manual.index,
        '$base/SupportedModesPublished': [true, true, true, true],
        '$base/HmiResponse/AckSequence': sequence,
        '$base/HmiResponse/Accepted': sequence != 0,
        '$base/HmiResponse/Diagnostic': '',
      },
    };
  }

  @override
  Future<bool> write(String path, OpcUaWriteType type, Object value) async {
    writes[path] = value;
    if (path.endsWith('/HmiRequest/Sequence')) {
      sequence = (value as num).toInt();
      if (!sequenceWritten.isCompleted) sequenceWritten.complete();
    }
    return true;
  }

  @override
  Future<void> close() async {}
}

class _LoginClient implements OpcUaSessionClient {
  final bool loginSucceeds;
  final Map<String, Object> writes = {};
  var sequence = 0;

  _LoginClient({required this.loginSucceeds});

  @override
  Future<Map<String, Object?>> snapshot() async {
    const base = 'PLC1/MAIN/PneumaticPress';
    final attempted = sequence != 0;
    final user = '${writes['$base/HmiRequest/User'] ?? ''}';
    return {
      'protocol': 'fraktal.opcua.snapshot.v1',
      'nodeCount': 16,
      'truncated': false,
      'rootChildren': ['4:PLC1(Object)'],
      'namespaces': [
        'http://opcfoundation.org/UA/',
        'urn:BeckhoffAutomation:Ua:PLC1',
      ],
      'values': {
        '$base/Status/Name': 'PneumaticPress',
        '$base/Status/ModuleType': ModuleType.unit.index,
        '$base/Status/State': ExecState.ready.index,
        '$base/ModeActivePublished': UnitMode.auto.index,
        '$base/SupportedModesPublished': [true, true, true, true],
        '$base/HmiResponse/AckSequence': sequence,
        '$base/HmiResponse/Accepted': attempted,
        '$base/HmiResponse/Diagnostic': '',
        '$base/Access/LoginFailed': attempted && !loginSucceeds,
        '$base/Access/CurrentLevel': attempted && loginSucceeds
            ? AccessLevel.admin.index
            : AccessLevel.none.index,
        '$base/Access/CurrentUser': attempted && loginSucceeds ? user : '',
      },
    };
  }

  @override
  Future<bool> write(String path, OpcUaWriteType type, Object value) async {
    writes[path] = value;
    if (path.endsWith('/HmiRequest/Sequence')) {
      sequence = (value as num).toInt();
    }
    return true;
  }

  @override
  Future<void> close() async {}
}

class _ReleaseClient implements OpcUaSessionClient {
  var sequence = 0;

  @override
  Future<Map<String, Object?>> snapshot() async {
    const base = 'PLC1/MAIN/PneumaticPress';
    return {
      'protocol': 'fraktal.opcua.snapshot.v1',
      'nodeCount': 22,
      'truncated': false,
      'rootChildren': ['4:PLC1(Object)'],
      'namespaces': [
        'http://opcfoundation.org/UA/',
        'urn:BeckhoffAutomation:Ua:PLC1',
      ],
      'values': {
        '$base/Status/Name': 'PneumaticPress',
        '$base/Status/ModuleType': ModuleType.unit.index,
        '$base/Status/State': ExecState.ready.index,
        '$base/ModeActivePublished': UnitMode.home.index,
        '$base/SupportedModesPublished': [true, true, true, true],
        '$base/HmiResponse/AckSequence': sequence,
        '$base/HmiResponse/Accepted': sequence != 0,
        '$base/HmiResponse/Diagnostic': '',
        '$base/HmiResponse/Report/Released': false,
        '$base/HmiResponse/Report/Count': sequence == 0 ? 0 : 2,
        '$base/HmiResponse/Report/Reasons/1/Description':
            'std.release.unitNotReady',
        '$base/HmiResponse/Report/Reasons/1/ReasonCode': 0,
        '$base/HmiResponse/Report/Reasons/1/SourcePath': 'PneumaticPress',
        '$base/HmiResponse/Report/Reasons/1/Kind': ReleaseKind.mode.index,
        '$base/HmiResponse/Report/Reasons/1/Bypassable': false,
        '$base/HmiResponse/Report/Reasons/2/Description':
            'std.release.controlDomainNotReady',
        '$base/HmiResponse/Report/Reasons/2/ReasonCode': 2002,
        '$base/HmiResponse/Report/Reasons/2/SourcePath': 'PneumaticPress',
        '$base/HmiResponse/Report/Reasons/2/Kind': ReleaseKind.interlock.index,
        '$base/HmiResponse/Report/Reasons/2/Bypassable': false,
      },
    };
  }

  @override
  Future<bool> write(String path, OpcUaWriteType type, Object value) async {
    if (path.endsWith('/HmiRequest/Sequence')) {
      sequence = (value as num).toInt();
    }
    return true;
  }

  @override
  Future<void> close() async {}
}
