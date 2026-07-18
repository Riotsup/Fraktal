import 'package:flutter_test/flutter_test.dart';

import 'package:fraktal_hmi/domain/fieldbus.dart';
import 'package:fraktal_hmi/localization/localization_controller.dart';

void main() {
  test('electrical tag stays exact while descriptions are localized', () {
    const channel = IoChannel(
      name: '_101B202A',
      descriptionKey: 'project.io.101B202A',
      address: 'EL1809 Ch5',
      path: 'PneumaticPress.IO._101B202A',
      modulePath: 'PneumaticPress.PressRam',
      dir: ChannelDir.input,
      kind: ChannelKind.digital,
      faultActive: true,
      diagnosticKey: 'project.error.pressDownSensorTimeout',
    );
    final localization = LocalizationController(
      enabledLanguages: {'en', 'es'},
      activeLanguage: 'es',
    );

    expect(channel.name, '_101B202A');
    expect(channel.address, 'EL1809 Ch5');
    expect(localization.resolve(channel.descriptionKey),
        'Sensor de prensa abajo.');
    expect(localization.resolve(channel.diagnosticKey), contains('_101B202A'));
  });
}
