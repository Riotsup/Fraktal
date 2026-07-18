import 'package:flutter_test/flutter_test.dart';
import '../lib/domain/types.dart';

void main() {
  test('default access policy covers every PLC gated-action ordinal', () {
    const session = AccessSession();

    expect(session.required, hasLength(GatedAction.values.length));
    for (final action in GatedAction.values) {
      expect(session.permits(action), isTrue,
          reason: '${action.name} must be open by default');
    }
  });

  test('short stale policy fails closed instead of throwing', () {
    const session = AccessSession(required: [AccessLevel.none]);

    expect(session.permits(GatedAction.dataRead), isTrue);
    expect(session.permits(GatedAction.alarmShelve), isFalse);
  });
}
