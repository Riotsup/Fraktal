/// §3.8a persistent-data editor + §8.3 history browser + §6.11 decision prompt.
library;

import '../localization/localized_text.dart';
import 'package:flutter/material.dart';
import '../domain/module_node.dart';
import '../domain/types.dart';
import '../state/app_state.dart';
import 'app_theme.dart';

/// §3.8a — editable persistent data. Model data (ParCfg) and station config
/// (StationCfg) are grouped separately; writing is gated by DATA_WRITE (7.7) and
/// re-checked in the PLC. Read-only below threshold (view still allowed if DATA_READ).
class ConfigEditor extends StatelessWidget {
  final AppState app;
  final ModuleNode node;
  const ConfigEditor({super.key, required this.app, required this.node});

  @override
  Widget build(BuildContext context) {
    if (node.config.isEmpty) return const SizedBox.shrink();
    final s = app.session;
    final canWrite = s.permits(GatedAction.dataWrite);
    final canRead = s.permits(GatedAction.dataRead);
    if (!canRead) {
      return const Card(
          child: ListTile(
              leading: Icon(Icons.lock_outline),
              title: LText('Configuration hidden (requires DATA_READ)')));
    }
    final par = node.config.where((c) => c.kind == CfgKind.parCfg).toList();
    final sta = node.config.where((c) => c.kind == CfgKind.stationCfg).toList();
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            const Icon(Icons.tune),
            const SizedBox(width: 8),
            LText('Configuration',
                style: Theme.of(context).textTheme.titleMedium),
            const Spacer(),
            if (!canWrite)
              const Chip(
                  avatar: Icon(Icons.lock_outline, size: 16),
                  label: LText('read-only')),
          ]),
          if (par.isNotEmpty) ...[
            const SizedBox(height: 6),
            LText('Model data (ParCfg) — versioned, per model',
                style: Theme.of(context).textTheme.labelMedium),
            for (final f in par) _row(context, f, canWrite),
          ],
          if (sta.isNotEmpty) ...[
            const SizedBox(height: 8),
            LText(
                'Station config (StationCfg) — per deployment, not in recipes',
                style: Theme.of(context).textTheme.labelMedium),
            for (final f in sta) _row(context, f, canWrite),
          ],
        ]),
      ),
    );
  }

  Widget _row(BuildContext context, CfgField f, bool canWrite) {
    var edited = f.value;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(children: [
        SizedBox(
            width: 160, child: LText(f.labelKey.isEmpty ? f.name : f.labelKey)),
        Expanded(
          child: TextFormField(
            initialValue: f.value,
            enabled: canWrite,
            decoration: InputDecoration(
              isDense: true,
              border: const OutlineInputBorder(),
              suffixText: f.unit.isEmpty ? null : f.unit,
            ),
            keyboardType: f.type == CfgType.number || f.type == CfgType.time
                ? TextInputType.number
                : TextInputType.text,
            onChanged: (value) => edited = value,
          ),
        ),
        if (canWrite)
          IconButton(
            tooltip: context.tr('Write to PLC (re-checked, 7.7)'),
            icon: const Icon(Icons.save_outlined),
            onPressed: () async {
              final ok = await app.repo.writeConfig(node.path, f, edited);
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                  content: LText(
                      ok ? '${f.name} saved' : '${f.name} rejected by PLC'),
                ));
              }
            },
          ),
      ]),
    );
  }
}

/// §8.3 — full event history browser (gated by ALARM_HISTORY), newest-first,
/// with durations and reset-class/state, filterable by severity.
class HistoryBrowser extends StatefulWidget {
  final ModuleNode node;
  const HistoryBrowser({super.key, required this.node});
  @override
  State<HistoryBrowser> createState() => _HistoryBrowserState();
}

class _HistoryBrowserState extends State<HistoryBrowser> {
  final Set<Severity> _show = {Severity.high, Severity.medium, Severity.low};
  @override
  Widget build(BuildContext context) {
    final events = widget.node.ringEvents
        .where((e) => _show.contains(e.severity))
        .toList();
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            const Icon(Icons.history),
            const SizedBox(width: 8),
            LText('Event history',
                style: Theme.of(context).textTheme.titleMedium),
            const Spacer(),
            for (final k in Severity.values)
              Padding(
                padding: const EdgeInsets.only(left: 4),
                child: FilterChip(
                  label: LText(k.name),
                  selected: _show.contains(k),
                  onSelected: (v) =>
                      setState(() => v ? _show.add(k) : _show.remove(k)),
                ),
              ),
          ]),
          const SizedBox(height: 8),
          if (events.isEmpty)
            const ListTile(dense: true, title: LText('No matching events'))
          else
            for (final e in events.take(50)) _row(context, e),
        ]),
      ),
    );
  }

  Widget _row(BuildContext context, AlarmEvent e) {
    final c = severityColor(context, e.severity);
    final dur = e.duration == null ? '' : '${e.duration!.inSeconds}s';
    return ListTile(
      dense: true,
      leading: Icon(
        switch (e.severity) {
          Severity.high => Icons.error,
          Severity.medium => Icons.warning_amber,
          Severity.low => Icons.info_outline
        },
        color: c,
      ),
      title: LText(e.description),
      subtitle: LText(
          '${e.sourcePath}${e.ioTag.isEmpty ? '' : ' · ${e.ioTag}${e.ioAddress.isEmpty ? '' : ' · ${e.ioAddress}'}'} · ${e.resetClass.name}'),
      trailing: LText(dur, style: Theme.of(context).textTheme.labelLarge),
    );
  }
}

/// §6.11 — operator decision prompt (typed request; answer written back).
class DecisionPrompt extends StatelessWidget {
  final AppState app;
  final ModuleNode node;
  const DecisionPrompt({super.key, required this.app, required this.node});
  @override
  Widget build(BuildContext context) {
    final d = node.decision;
    if (d == null || !d.pending) return const SizedBox.shrink();
    final cs = Theme.of(context).colorScheme;
    return Card(
      color: cs.tertiaryContainer,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            const Icon(Icons.help_outline),
            const SizedBox(width: 8),
            LText('Operator decision',
                style: Theme.of(context).textTheme.titleMedium)
          ]),
          const SizedBox(height: 6),
          LText(d.prompt),
          const SizedBox(height: 8),
          Wrap(spacing: 8, children: [
            for (var i = 0; i < d.options.length; i++)
              FilledButton.tonal(
                onPressed: () => app.repo.setDecisionAnswer(node.path, i + 1),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  LText(d.options[i]),
                  if (i == d.defaultOption)
                    const LText('std.decision.defaultSuffix'),
                ]),
              ),
          ]),
        ]),
      ),
    );
  }
}
