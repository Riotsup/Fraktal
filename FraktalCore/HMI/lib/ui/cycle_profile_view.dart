/// §8.11.4 cycle-time profile — waterfall of the last cycle, coloured by time
/// class, with the Total vs Work (real cycle time) vs Wait split in the header.
/// Pure CustomPaint; no charting package.
library;

import '../localization/localized_text.dart';
import 'package:flutter/material.dart';
import '../domain/types.dart';

// Categorical palette validated with the dataviz six-checks (light PASS; dark
// passes with a contrast WARN on blocked, relieved by direct labels + the table
// views these charts always carry). Fixed assignment — never re-ordered.
Color timeClassColor(TimeClass c) {
  switch (c) {
    case TimeClass.work:
      return const Color(0xFF2E7D32); // green: value-adding
    case TimeClass.waitUpstream:
      return const Color(0xFF1565C0); // blue: starved
    case TimeClass.waitDownstream:
      return const Color(0xFFAD1457); // magenta: blocked
    case TimeClass.waitOperator:
      return const Color(0xFFB26A00); // amber: operator
    case TimeClass.waitExternal:
      return const Color(0xFF0097A7); // teal: host/tool
  }
}

String timeClassLabel(TimeClass c) => switch (c) {
      TimeClass.work => 'Work',
      TimeClass.waitUpstream => 'Wait ↑ (starved)',
      TimeClass.waitDownstream => 'Wait ↓ (blocked)',
      TimeClass.waitOperator => 'Wait operator',
      TimeClass.waitExternal => 'Wait external',
    };

class CycleProfileView extends StatelessWidget {
  final CycleProfile profile;
  const CycleProfileView({super.key, required this.profile});

  @override
  Widget build(BuildContext context) {
    final p = profile;
    if (p.steps.isEmpty) return const SizedBox.shrink();
    final maxMs = p.steps
        .map((s) => s.duration.inMilliseconds)
        .fold<int>(1, (a, b) => a > b ? a : b);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            const Icon(Icons.timeline),
            const SizedBox(width: 8),
            LText('Cycle #${p.cycleNo}',
                style: Theme.of(context).textTheme.titleMedium),
            const Spacer(),
            _stat(context, 'Total', p.total),
            _stat(context, 'Work', p.workTime,
                color: timeClassColor(TimeClass.work)),
            _stat(context, 'Wait', p.waitTime, color: const Color(0xFF1565C0)),
          ]),
          const SizedBox(height: 12),
          for (final s in p.steps) _bar(context, s, maxMs),
          const SizedBox(height: 8),
          Wrap(spacing: 12, runSpacing: 4, children: [
            for (final c in TimeClass.values)
              if (p.steps.any((s) => s.timeClass == c)) _legend(c),
          ]),
        ]),
      ),
    );
  }

  Widget _stat(BuildContext ctx, String label, Duration d, {Color? color}) {
    return Padding(
      padding: const EdgeInsets.only(left: 16),
      child: Column(children: [
        LText(label, style: Theme.of(ctx).textTheme.labelSmall),
        LText('${(d.inMilliseconds / 1000).toStringAsFixed(1)}s',
            style: Theme.of(ctx).textTheme.titleMedium?.copyWith(color: color)),
      ]),
    );
  }

  Widget _bar(BuildContext ctx, StepTiming s, int maxMs) {
    final frac = s.duration.inMilliseconds / maxMs;
    // §8.11.4(c): ExpectedTime drawn against the actual — a tick at the declared
    // guard; a step past its guard gets an outline so the overrun pops out.
    final hasExpected = s.expected > Duration.zero;
    final expectedFrac = hasExpected
        ? (s.expected.inMilliseconds / maxMs).clamp(0.0, 1.0)
        : 0.0;
    final overrun = hasExpected && s.duration > s.expected;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(children: [
        SizedBox(
            width: 44,
            child: LText('${s.stepNo}',
                style: Theme.of(ctx).textTheme.labelMedium)),
        SizedBox(
            width: 120,
            child: LText(s.stepName, overflow: TextOverflow.ellipsis)),
        Expanded(
          child: LayoutBuilder(builder: (_, box) {
            return Stack(children: [
              Container(
                  height: 20,
                  decoration: BoxDecoration(
                      color: Theme.of(ctx).colorScheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(4))),
              Container(
                height: 20,
                width: (box.maxWidth * frac).clamp(2.0, box.maxWidth),
                decoration: BoxDecoration(
                    color: timeClassColor(s.timeClass),
                    borderRadius: BorderRadius.circular(4),
                    border: overrun
                        ? Border.all(
                            color: Theme.of(ctx).colorScheme.error, width: 2)
                        : null),
              ),
              if (hasExpected)
                Positioned(
                  left: (box.maxWidth * expectedFrac - 1)
                      .clamp(0.0, box.maxWidth - 2),
                  child: Container(
                      width: 2,
                      height: 20,
                      color: Theme.of(ctx).colorScheme.onSurfaceVariant),
                ),
            ]);
          }),
        ),
        const SizedBox(width: 8),
        SizedBox(
            width: 52,
            child: LText(
                '${(s.duration.inMilliseconds / 1000).toStringAsFixed(1)}s',
                textAlign: TextAlign.right,
                style: overrun
                    ? TextStyle(color: Theme.of(ctx).colorScheme.error)
                    : null)),
      ]),
    );
  }

  Widget _legend(TimeClass c) => Row(mainAxisSize: MainAxisSize.min, children: [
        Container(
            width: 12,
            height: 12,
            decoration: BoxDecoration(
                color: timeClassColor(c),
                borderRadius: BorderRadius.circular(3))),
        const SizedBox(width: 4),
        LText(timeClassLabel(c), style: const TextStyle(fontSize: 12)),
      ]);
}
