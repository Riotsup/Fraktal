import 'package:flutter_test/flutter_test.dart';
import 'package:fraktal_hmi/domain/connection_settings.dart';

void main() {
  test('connection settings persist the administrator-selected Unit scope', () {
    const settings = ConnectionSettings(
      everConnected: true,
      selectedUnitPaths: ['StationA', 'ConveyorB'],
      unitSelectionComplete: true,
    );
    final restored = ConnectionSettings.fromJson(settings.toJson());

    expect(restored?.selectedUnitPaths, ['StationA', 'ConveyorB']);
    expect(restored?.unitSelectionComplete, isTrue);
  });

  test('schema 1 settings migrate to an incomplete Unit selection', () {
    final restored = ConnectionSettings.fromJson({
      'schemaVersion': 1,
      'transport': 'gateway',
      'endpoint': 'ws://127.0.0.1/fraktal',
      'everConnected': true,
    });

    expect(restored?.everConnected, isTrue);
    expect(restored?.selectedUnitPaths, isEmpty);
    expect(restored?.unitSelectionComplete, isFalse);
  });
}
