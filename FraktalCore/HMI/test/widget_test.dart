// Smoke test: the app boots against the shipped SimRepository (the O6 pattern —
// full UI exercised with zero infrastructure) and renders the shell.
import 'package:flutter_test/flutter_test.dart';

import 'package:fraktal_hmi/data/sim_repository.dart';
import 'package:fraktal_hmi/main.dart';
import 'package:fraktal_hmi/state/app_state.dart';

void main() {
  testWidgets('App boots against SimRepository and renders', (tester) async {
    final app = AppState(SimRepository());
    await tester.pumpWidget(FraktalHmiApp(app: app));
    await tester
        .pump(const Duration(seconds: 2)); // let the sim publish a frame
    expect(find.byType(FraktalHmiApp), findsOneWidget);
    app.dispose();
  });
}
