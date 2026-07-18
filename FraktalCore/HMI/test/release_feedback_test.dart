import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fraktal_hmi/data/sim_repository.dart';
import 'package:fraktal_hmi/domain/types.dart';
import 'package:fraktal_hmi/localization/localized_text.dart';
import 'package:fraktal_hmi/state/app_state.dart';
import 'package:fraktal_hmi/ui/release_panel.dart';

void main() {
  testWidgets('release panel opens immediately and does not snapshot-loop',
      (tester) async {
    final repository = _ControlledReleaseRepository();
    final app = AppState(repository);

    await tester.pumpWidget(LocalizationScope(
      controller: app.localization,
      child: MaterialApp(
        home: AnimatedBuilder(
          animation: app,
          builder: (_, __) => Scaffold(body: ReleasePanel(app: app)),
        ),
      ),
    ));

    final query = app.showReleaseReportStart('StationA');
    await tester.pump();
    expect(find.text('Checking release conditions…'), findsOneWidget);

    repository.release.complete(const ReleaseReport(false, [
      ReleaseReason('std.release.controlPowerOff', ReleaseKind.interlock),
    ]));
    await query;
    await tester.pump();
    expect(find.text('Control power is off.'), findsOneWidget);

    // SimRepository continues publishing forest snapshots. They must not each
    // become a new PLC release mailbox transaction.
    await tester.pump(const Duration(milliseconds: 1500));
    expect(repository.releaseCalls, 1);

    app.clearRelease();
    app.dispose();
    await tester.pumpWidget(const SizedBox.shrink());
  });
}

class _ControlledReleaseRepository extends SimRepository {
  final release = Completer<ReleaseReport>();
  var releaseCalls = 0;

  @override
  Future<ReleaseReport> releaseReportStart(String unitPath) {
    releaseCalls++;
    return release.future;
  }
}
