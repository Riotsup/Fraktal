import 'package:flutter_test/flutter_test.dart';
import 'package:fraktal_hmi/data/opcua_snapshot_mapper.dart';
import 'package:fraktal_hmi/domain/types.dart';

void main() {
  test('discovers a generic Unit and nested CM from Status contract members',
      () {
    final projection = OpcUaSnapshotMapper().map({
      'protocol': 'fraktal.opcua.snapshot.v1',
      'values': {
        'PLC1/MAIN/PneumaticPress/Status/Name': 'PneumaticPress',
        'PLC1/MAIN/PneumaticPress/Status/ModuleType': 1,
        'PLC1/MAIN/PneumaticPress/Status/State': 1,
        'PLC1/MAIN/PneumaticPress/Status/FaultActive': false,
        'PLC1/MAIN/PneumaticPress/Status/TileEnable': true,
        'PLC1/MAIN/PneumaticPress/ModeActivePublished': 0,
        'PLC1/MAIN/PneumaticPress/RunningPublished': true,
        'PLC1/MAIN/PneumaticPress/SupportedModesPublished': [
          true,
          true,
          true,
          true,
          false,
          false,
          false
        ],
        'PLC1/MAIN/PneumaticPress/AvailableModelCount': 3,
        'PLC1/MAIN/PneumaticPress/AvailableModels/1/ModelCode': 'ALUMINUM',
        'PLC1/MAIN/PneumaticPress/AvailableModels/2/ModelCode': 'PLASTIC',
        'PLC1/MAIN/PneumaticPress/AvailableModels/3/ModelCode': 'STEEL',
        'PLC1/MAIN/PneumaticPress/CurrentStep/StepNo': 880,
        'PLC1/MAIN/PneumaticPress/CurrentStep/StepName':
            'project.step.pressChangeoverAwaitConfirmation',
        'PLC1/MAIN/PneumaticPress/CurrentStep/Class': 3,
        'PLC1/MAIN/PneumaticPress/CurrentStep/ExpectedTime': 0,
        'PLC1/MAIN/PneumaticPress/CurrentStep/Conds/1/Label':
            'project.condition.pressChangeoverConfirmation',
        'PLC1/MAIN/PneumaticPress/CurrentStep/Conds/1/Ok': false,
        'PLC1/MAIN/PneumaticPress/Decision/Prompt':
            'project.decision.pressChangeoverConfirm',
        'PLC1/MAIN/PneumaticPress/Decision/Options': [
          'project.decision.confirmChangeover',
          'project.decision.repeatChangeoverPosition',
          '',
          '',
          '',
          ''
        ],
        'PLC1/MAIN/PneumaticPress/Decision/Default': 0,
        'PLC1/MAIN/PneumaticPress/SupportedRunStylesPublished': [
          true,
          true,
          false
        ],
        'PLC1/MAIN/PneumaticPress/Access/CurrentLevel': 3,
        'PLC1/MAIN/PneumaticPress/Access/CurrentUser': 'engineer',
        'PLC1/MAIN/PneumaticPress/Access/Policy/Required':
            List<int>.filled(11, 0),
        'PLC1/MAIN/PneumaticPress/PressRam/Status/Name':
            'PneumaticPress.PressRam',
        'PLC1/MAIN/PneumaticPress/PressRam/Status/ModuleType': 3,
        'PLC1/MAIN/PneumaticPress/PressRam/Status/State': 0,
        'PLC1/MAIN/PneumaticPress/PressRam/Status/TileEnable': true,
      },
    });

    expect(projection.forest, hasLength(1));
    final root = projection.forest.single;
    expect(root.path, 'PneumaticPress');
    expect(root.type, ModuleType.unit);
    expect(root.modeActive, UnitMode.auto);
    expect(root.running, isTrue);
    expect(root.supportedModes,
        [UnitMode.auto, UnitMode.manual, UnitMode.home, UnitMode.changeover]);
    expect(root.availableModels, ['ALUMINUM', 'PLASTIC', 'STEEL']);
    expect(root.step?.stepNo, 880);
    expect(root.step?.timeClass, TimeClass.waitOperator);
    expect(root.step?.conds.single.ok, isFalse);
    expect(root.decision?.prompt, 'project.decision.pressChangeoverConfirm');
    expect(root.decision?.options, hasLength(2));
    expect(root.supportedRunStyles, [RunStyle.continuous, RunStyle.singleStep]);
    expect(root.access?.level, AccessLevel.engineer);
    expect(root.children.single.path, 'PneumaticPress.PressRam');
    expect(projection.browsePathByModulePath['PneumaticPress.PressRam'],
        'PLC1/MAIN/PneumaticPress/PressRam');
  });

  test('rejects arbitrary OPC UA trees without the Fraktal Status contract',
      () {
    final projection = OpcUaSnapshotMapper().map({
      'values': {'Objects/Server/ServerStatus/State': 0},
    });
    expect(projection.forest, isEmpty);
  });

  test('keeps the direct root and discards TF6100 reference aliases', () {
    final projection = OpcUaSnapshotMapper().map({
      'values': {
        'PLC1/MAIN/PneumaticPress/Status/Name': 'PneumaticPress',
        'PLC1/MAIN/PneumaticPress/Status/ModuleType': ModuleType.unit.index,
        'PLC1/MAIN/PneumaticPress/ModeActivePublished': UnitMode.auto.index,
        'PLC1/MAIN/PneumaticPress/PressRam/Status/Name':
            'PneumaticPress.PressRam',
        'PLC1/MAIN/PneumaticPress/PressRam/Status/ModuleType':
            ModuleType.controlModule.index,
        // REFERENCE TO alias: browse name and Fraktal identity disagree.
        'PLC1/MAIN/RecipeCatalog/UnitRef/Status/Name': 'PneumaticPress',
        'PLC1/MAIN/RecipeCatalog/UnitRef/Status/ModuleType':
            ModuleType.unit.index,
        // A same-named owner alias still loses to the shallower direct root.
        'PLC1/MAIN/IoDriver/PneumaticPress/Status/Name': 'PneumaticPress',
        'PLC1/MAIN/IoDriver/PneumaticPress/Status/ModuleType':
            ModuleType.unit.index,
      },
    });

    expect(projection.forest, hasLength(1));
    expect(projection.forest.single.path, 'PneumaticPress');
    expect(projection.forest.single.children.single.path,
        'PneumaticPress.PressRam');
    expect(projection.browsePathByModulePath['PneumaticPress'],
        'PLC1/MAIN/PneumaticPress');
    expect(projection.discardedAliases, hasLength(2));
  });
}
