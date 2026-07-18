/// Optional facet cards — each renders only when the module publishes that facet
/// (Core 3.10 self-description). Covers the data-bearing annexes:
///   D link supervision · E traceability/verdict · F PackML · G/I motion.
library;

import '../localization/localized_text.dart';
import 'package:flutter/material.dart';
import '../domain/types.dart';

class SafetyCard extends StatelessWidget {
  final SafetyFacet safety;
  const SafetyCard({super.key, required this.safety});
  @override
  Widget build(BuildContext context) {
    final warning = safety.demandActive ||
        safety.resetRequired ||
        safety.faultActive ||
        safety.bridgeActive ||
        safety.mutingActive;
    final cs = Theme.of(context).colorScheme;
    return Card(
      color: warning ? cs.errorContainer : null,
      child: Padding(
          padding: const EdgeInsets.all(12),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              const Icon(Icons.health_and_safety_outlined),
              const SizedBox(width: 8),
              LText('Safety', style: Theme.of(context).textTheme.titleMedium),
              const Spacer(),
              Chip(label: LText(safety.allSafe ? 'READY' : 'SAFE STATE'))
            ]),
            if (safety.bridgeActive)
              const ListTile(
                  dense: true,
                  leading: Icon(Icons.key),
                  title: LText('KEY BRIDGE ACTIVE')),
            if (safety.mutingActive)
              const ListTile(
                  dense: true,
                  leading: Icon(Icons.visibility_off_outlined),
                  title: LText('MUTING ACTIVE')),
            if (safety.resetRequired)
              const ListTile(
                  dense: true,
                  leading: Icon(Icons.restart_alt),
                  title: LText('Physical safety reset required')),
            for (final d in safety.devices)
              ListTile(
                  dense: true,
                  leading: Icon(
                      d.ready
                          ? Icons.check_circle_outline
                          : Icons.gpp_bad_outlined,
                      color: d.ready ? const Color(0xFF2E7D32) : cs.error),
                  title: LText(d.name),
                  subtitle: LText(
                      '${d.kind.name} · ${d.state.name}${d.description.isEmpty ? '' : '\n${context.tr(d.description)}'}'),
                  trailing: d.affectedPowerMask == 0
                      ? null
                      : LText(
                          'Zones 0x${d.affectedPowerMask.toRadixString(16)}')),
          ])),
    );
  }
}

class ControlPowerCard extends StatelessWidget {
  final ControlPowerFacet power;
  final String domainId;
  final String domainName;
  final List<String> memberUnits;
  final bool canControl;
  final Future<bool> Function() onControlOn, onControlOff;
  const ControlPowerCard(
      {super.key,
      required this.power,
      this.domainId = '',
      this.domainName = '',
      this.memberUnits = const [],
      required this.canControl,
      required this.onControlOn,
      required this.onControlOff});
  @override
  Widget build(BuildContext context) => Card(
      child: Padding(
          padding: const EdgeInsets.all(12),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              const Icon(Icons.power_settings_new),
              const SizedBox(width: 8),
              LText('Control power',
                  style: Theme.of(context).textTheme.titleMedium),
              const Spacer(),
              FilledButton.tonal(
                  onPressed:
                      canControl && !power.controlOn ? onControlOn : null,
                  child: const LText('Control On')),
              const SizedBox(width: 8),
              OutlinedButton(
                  onPressed:
                      canControl && power.controlOn ? onControlOff : null,
                  child: const LText('Control Off'))
            ]),
            if (domainId.isNotEmpty)
              ListTile(
                dense: true,
                leading: const Icon(Icons.fence_outlined),
                title: LText(domainName.isEmpty ? domainId : domainName),
                subtitle: LText(
                    'Shared control domain $domainId · affects ${memberUnits.isEmpty ? 'this Unit' : memberUnits.join(', ')}'),
              ),
            if (power.rearmRequired)
              const ListTile(
                  dense: true,
                  leading: Icon(Icons.warning_amber),
                  title: LText('Deliberate rearm required')),
            for (final g in power.groups)
              ListTile(
                  dense: true,
                  leading: Icon(g.powerOn ? Icons.bolt : Icons.power_off),
                  title: LText(g.name),
                  subtitle: LText(
                      '${g.kind.name} · ${g.state.name} · safety ${g.safetyPermit ? 'permitted' : 'withheld'} · bus ${g.fieldbusHealthy ? 'healthy' : 'fault'}'),
                  trailing: g.rearmRequired
                      ? const Chip(label: LText('REARM'))
                      : null),
          ])));
}

/// Annex D — external device link status.
class LinkCard extends StatelessWidget {
  final LinkFacet link;
  const LinkCard({super.key, required this.link});
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Card(
      child: ListTile(
        leading: Icon(link.linked ? Icons.link : Icons.link_off,
            color: link.linked ? const Color(0xFF2E7D32) : cs.error),
        title: LText(link.linked ? 'Device linked' : 'Link lost'),
        subtitle: LText(link.linked
            ? 'Last seen ${_ago(link.lastSeen)}'
            : (link.linkReason.isEmpty ? 'No heartbeat' : link.linkReason)),
      ),
    );
  }

  String _ago(DateTime? t) {
    if (t == null) return '—';
    final s = DateTime.now().difference(t).inSeconds;
    return s <= 1 ? 'just now' : '${s}s ago';
  }
}

/// Annex F — PackML state chip row (ISA-TR88.00.02).
class PackMLCard extends StatelessWidget {
  final PackMLState state;
  const PackMLCard({super.key, required this.state});
  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(children: [
          const Icon(Icons.account_tree_outlined),
          const SizedBox(width: 10),
          LText('PackML', style: Theme.of(context).textTheme.titleSmall),
          const Spacer(),
          Chip(
              label: LText(state.name.toUpperCase()),
              backgroundColor: _bg(context)),
        ]),
      ),
    );
  }

  Color? _bg(BuildContext ctx) {
    switch (state) {
      case PackMLState.execute:
        return const Color(0xFFC8E6C9);
      case PackMLState.held:
      case PackMLState.holding:
      case PackMLState.suspended:
        return const Color(0xFFFFE0B2);
      case PackMLState.aborted:
      case PackMLState.stopped:
        return Theme.of(ctx).colorScheme.errorContainer;
      default:
        return null;
    }
  }
}

/// Annex G / I — axis / robot published motion.
class MotionCard extends StatelessWidget {
  final MotionFacet m;
  const MotionCard({super.key, required this.m});
  @override
  Widget build(BuildContext context) {
    final range = (m.targetPosition == 0) ? 1.0 : m.targetPosition;
    final frac = (m.actualPosition / range).clamp(0.0, 1.0);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Icon(m.moving
                ? Icons.play_circle_outline
                : Icons.pause_circle_outline),
            const SizedBox(width: 8),
            LText('Motion', style: Theme.of(context).textTheme.titleSmall),
            const Spacer(),
            if (m.homed)
              const Chip(label: LText('HOMED'))
            else
              const Chip(label: LText('NOT HOMED')),
          ]),
          const SizedBox(height: 8),
          LinearProgressIndicator(value: frac),
          const SizedBox(height: 6),
          LText('Actual ${m.actualPosition.toStringAsFixed(2)} ${m.unit}  ·  '
              'Target ${m.targetPosition.toStringAsFixed(2)} ${m.unit}  ·  '
              'v ${m.actualVelocity.toStringAsFixed(1)} ${m.unit}/s'),
        ]),
      ),
    );
  }
}

/// Annex E — part context, verdict, and measured records with limits.
class PartCard extends StatelessWidget {
  final PartFacet part;
  const PartCard({super.key, required this.part});
  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            const Icon(Icons.inventory_2_outlined),
            const SizedBox(width: 8),
            LText('Part ${part.uid.isEmpty ? '(none)' : part.uid}',
                style: Theme.of(context).textTheme.titleSmall),
            const Spacer(),
            _verdictChip(context, part.verdict),
          ]),
          if (part.verdict == Verdict.nok && part.reason.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: LText(part.reason,
                  style: TextStyle(color: Theme.of(context).colorScheme.error)),
            ),
          const SizedBox(height: 6),
          for (final r in part.records) _measRow(context, r),
        ]),
      ),
    );
  }

  Widget _verdictChip(BuildContext ctx, Verdict v) {
    final (label, color) = switch (v) {
      Verdict.ok => ('OK', const Color(0xFF2E7D32)),
      Verdict.nok => ('NOK', Theme.of(ctx).colorScheme.error),
      Verdict.rework => ('REWORK', const Color(0xFFB26A00)),
      Verdict.none => ('—', Colors.grey),
    };
    return Chip(
        label: LText(label),
        backgroundColor: color.withValues(alpha: 0.15),
        side: BorderSide(color: color));
  }

  Widget _measRow(BuildContext ctx, MeasRecord r) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(children: [
        SizedBox(
            width: 120, child: LText(r.name, overflow: TextOverflow.ellipsis)),
        Expanded(
          child: LText('${r.value.toStringAsFixed(2)} ${r.unit}  '
              '(${r.min.toStringAsFixed(1)}–${r.max.toStringAsFixed(1)})'),
        ),
        Icon(r.inTol ? Icons.check_circle_outline : Icons.error_outline,
            size: 18,
            color: r.inTol
                ? const Color(0xFF2E7D32)
                : Theme.of(ctx).colorScheme.error),
      ]),
    );
  }
}

/// §3.10.1 digital nameplate facet — asset identity, versions, documentation link.
class NameplateCard extends StatelessWidget {
  final Nameplate plate;
  const NameplateCard({super.key, required this.plate});
  @override
  Widget build(BuildContext context) {
    final rows = <(String, String)>[
      if (plate.manufacturer.isNotEmpty) ('Manufacturer', plate.manufacturer),
      if (plate.designation.isNotEmpty) ('Product', plate.designation),
      if (plate.serial.isNotEmpty) ('Serial', plate.serial),
      if (plate.year.isNotEmpty) ('Year', plate.year),
      if (plate.hwVersion.isNotEmpty) ('Hardware', plate.hwVersion),
      if (plate.fwVersion.isNotEmpty) ('Firmware', plate.fwVersion),
      if (plate.swVersion.isNotEmpty) ('Software', plate.swVersion),
      if (plate.orderCode.isNotEmpty) ('Order code', plate.orderCode),
    ];
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            const Icon(Icons.badge_outlined),
            const SizedBox(width: 8),
            LText('Nameplate', style: Theme.of(context).textTheme.titleMedium),
            const Spacer(),
            if (plate.docUrl.isNotEmpty)
              Tooltip(
                message: plate.docUrl,
                child: TextButton.icon(
                  icon: const Icon(Icons.menu_book_outlined, size: 18),
                  label: const LText('Docs'),
                  onPressed: () => ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                          content: LText('Documentation: ${plate.docUrl}'))),
                ),
              ),
          ]),
          const SizedBox(height: 4),
          for (final (k, v) in rows)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Row(children: [
                SizedBox(
                    width: 110,
                    child:
                        LText(k, style: Theme.of(context).textTheme.bodySmall)),
                Expanded(child: LText(v)),
              ]),
            ),
        ]),
      ),
    );
  }
}

/// §8.5.1 OEE facet — A/P/Q + OEE with exception-based colouring (muted at/above
/// target, colour only below — ISA-101 style) and a sparkline of recent samples.
/// Invalid factors render as '—', never 100%.
class OeeCard extends StatelessWidget {
  final OeeSnapshot oee;
  final VoidCallback onReset; // act-or-explain handled by the caller
  const OeeCard({super.key, required this.oee, required this.onReset});

  static const _target = 0.85;

  Color _tone(BuildContext ctx, double v, bool valid) {
    if (!valid) return Theme.of(ctx).colorScheme.outline;
    if (v >= _target)
      return Theme.of(ctx).colorScheme.onSurfaceVariant; // muted = good
    if (v >= 0.6) return const Color(0xFFB26A00);
    return Theme.of(ctx).colorScheme.error;
  }

  String _pct(double v, bool valid) =>
      valid ? '${(v * 100).toStringAsFixed(1)}%' : '—';

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            const Icon(Icons.speed_outlined),
            const SizedBox(width: 8),
            LText('OEE', style: Theme.of(context).textTheme.titleMedium),
            const Spacer(),
            LText(_pct(oee.oee, oee.oeeValid),
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    color: _tone(context, oee.oee, oee.oeeValid),
                    fontWeight: FontWeight.w700)),
            IconButton(
                tooltip: context.tr('Reset OEE (shift start, logged)'),
                icon: const Icon(Icons.restart_alt, size: 20),
                onPressed: onReset),
          ]),
          Row(children: [
            _factor(context, 'Availability', oee.availability, oee.availValid),
            _factor(context, 'Performance', oee.performance, oee.perfValid),
            _factor(context, 'Quality', oee.quality, oee.qualValid),
          ]),
          if (oee.trend.length >= 2) ...[
            const SizedBox(height: 8),
            SizedBox(
                height: 36,
                width: double.infinity,
                child: CustomPaint(
                    painter: _Sparkline(
                        oee.trend, Theme.of(context).colorScheme.primary))),
          ],
        ]),
      ),
    );
  }

  Widget _factor(BuildContext context, String label, double v, bool valid) {
    return Expanded(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        LText(label, style: Theme.of(context).textTheme.bodySmall),
        LText(_pct(v, valid),
            style: TextStyle(
                fontWeight: FontWeight.w600, color: _tone(context, v, valid))),
        LinearProgressIndicator(
            value: valid ? v : 0,
            minHeight: 4,
            color: _tone(context, v, valid)),
      ]),
    );
  }
}

class _Sparkline extends CustomPainter {
  final List<double> data;
  final Color color;
  _Sparkline(this.data, this.color);
  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()
      ..color = color
      ..strokeWidth = 1.6
      ..style = PaintingStyle.stroke;
    final path = Path();
    for (var i = 0; i < data.length; i++) {
      final x = i / (data.length - 1) * size.width;
      final y = size.height - (data[i].clamp(0.0, 1.0)) * size.height;
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }
    canvas.drawPath(path, p);
  }

  @override
  bool shouldRepaint(covariant _Sparkline old) =>
      old.data != data || old.color != color;
}
