/// Right-hand detail: header + Status/PLCopen strip, then whichever facets the
/// module publishes (link/part/PackML/motion — the data-bearing annexes), the
/// §6.11 decision prompt, Unit controls (mode/start/stop, blocked banner),
/// §8.11.4 cycle profile, §3.8a config editor, and §8.3 history. All writes are
/// access-gated (7.7) and re-checked in the PLC.
library;

import 'package:flutter/material.dart';
import '../domain/module_node.dart';
import '../domain/types.dart';
import '../state/app_state.dart';
import '../content/module_content_controller.dart';
import '../localization/localized_text.dart';
import 'app_theme.dart';
import 'cycle_profile_view.dart';
import 'cycle_trend_view.dart';
import 'config_and_history.dart';
import 'facet_cards.dart';
import 'overview_and_indicators.dart';
import 'module_information.dart';

class ModuleDetail extends StatelessWidget {
  final AppState app;
  const ModuleDetail({super.key, required this.app});

  @override
  Widget build(BuildContext context) {
    final n = app.selected;
    if (n == null) return const Center(child: LText('Select a module'));
    final s = app.session;
    final operations =
        app.content.permits(n.path, ModuleSection.operations, s.level);
    final diagnostics =
        app.content.permits(n.path, ModuleSection.diagnostics, s.level);
    final configuration =
        app.content.permits(n.path, ModuleSection.configuration, s.level);
    final history = app.content.permits(n.path, ModuleSection.history, s.level);
    return ListView(padding: const EdgeInsets.all(16), children: [
      Row(children: [
        Container(
            width: 14,
            height: 14,
            decoration: BoxDecoration(
                color: stateColor(context, n.state), shape: BoxShape.circle)),
        const SizedBox(width: 10),
        Expanded(
            child: LText(n.path,
                style: Theme.of(context).textTheme.titleLarge,
                overflow: TextOverflow.ellipsis)),
        Chip(label: LText(n.state.name.toUpperCase())),
      ]),
      ModuleInformationCard(app: app, node: n),
      ModuleDocumentsCard(app: app, node: n),
      if (diagnostics && n.message.isNotEmpty)
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: LText(n.message,
              style: TextStyle(
                  color: n.faultActive
                      ? Theme.of(context).colorScheme.error
                      : null)),
        ),
      if (diagnostics && n.diagnosticIoTag.isNotEmpty)
        Align(
          alignment: Alignment.centerLeft,
          child: Chip(
            avatar: const Icon(Icons.sensors, size: 18),
            label: Text(n.diagnosticIoAddress.isEmpty
                ? n.diagnosticIoTag
                : '${n.diagnosticIoTag} · ${n.diagnosticIoAddress}'),
          ),
        ),
      if (operations) DecisionPrompt(app: app, node: n),
      if (operations && n.step != null) CurrentStepCard(step: n.step!),
      if (diagnostics && n.link != null) LinkCard(link: n.link!),
      if (diagnostics && n.packML != null) PackMLCard(state: n.packML!),
      if (diagnostics && n.motion != null) MotionCard(m: n.motion!),
      if (diagnostics && n.part != null) PartCard(part: n.part!),
      if (diagnostics && n.safety != null) SafetyCard(safety: n.safety!),
      if (operations && n.controlPower != null)
        ControlPowerCard(
          power: n.controlPower!,
          domainId: n.controlDomainId,
          domainName: n.controlDomainName,
          memberUnits: n.controlDomainMembers,
          canControl: s.permits(GatedAction.powerControl),
          onControlOn: () => app.repo.controlOn(n.path),
          onControlOff: () => app.repo.controlOff(n.path),
        ),
      if (diagnostics && n.nameplate != null && !n.nameplate!.isEmpty)
        NameplateCard(plate: n.nameplate!),
      if (diagnostics && n.oee != null)
        OeeCard(
          oee: n.oee!,
          onReset: () async {
            // §7.8 act-or-explain: blocked reset opens the release panel
            if (!app.session.permits(GatedAction.dataWrite)) {
              app.showReleaseReportAction(
                  n.path, GatedAction.dataWrite, 'OEE reset blocked');
              return;
            }
            final ok = await app.repo.resetOee(n.path);
            if (!ok)
              app.showReleaseReportAction(
                  n.path, GatedAction.dataWrite, 'OEE reset blocked');
          },
        ),
      if (operations && n.commands.isNotEmpty) _manualPanel(context, n),
      if (operations && n.isUnit) ...[
        const SizedBox(height: 12),
        if (n.blocking)
          MaterialBanner(
            backgroundColor: Theme.of(context).colorScheme.errorContainer,
            content: const LText(
                'Blocked — a manual-reset event awaits operator intervention (8.3)'),
            actions: [
              FilledButton(
                onPressed: s.permits(GatedAction.alarmReset)
                    ? () => app.repo.operatorReset(n.path)
                    : () => app.showReleaseReportAction(
                        n.path, GatedAction.alarmReset, 'Reset blocked'),
                child: const LText('Operator reset'),
              ),
            ],
          ),
        Wrap(spacing: 8, runSpacing: 8, children: [
          Chip(
              avatar: const Icon(Icons.qr_code_2, size: 18),
              label: LText('Model ${n.modelCode}')),
          Chip(label: LText('Mode ${n.modeActive?.name.toUpperCase() ?? '-'}')),
          if (n.machineState != null)
            Chip(
                avatar: const Icon(Icons.factory_outlined, size: 18),
                label: LText(n.machineState!.name.toUpperCase())),
          Chip(label: LText('Good ${n.goodCount}')),
          Chip(label: LText('NOK ${n.nokCount}')),
          if (n.reworkCount > 0)
            Chip(label: LText('Rework ${n.reworkCount}')),
          if (n.lastCycleTime > Duration.zero)
            Chip(
                avatar: const Icon(Icons.timer_outlined, size: 18),
                label: LText(
                    'Cycle ${(n.lastCycleTime.inMilliseconds / 1000).toStringAsFixed(1)}s'
                    ' (best ${(n.minCycleTime.inMilliseconds / 1000).toStringAsFixed(1)}s)')),
        ]),
        const SizedBox(height: 8),
        _controls(context, n, s),
        const SizedBox(height: 12),
        // §8.11.4(c) cycle-time analysis: trend (why it moved) -> waterfall
        // (which step) -> Pareto (which step, over time) -> command timing
        // per child module (which command) below.
        CycleTrendView(history: n.cycleHistory, minCycleTime: n.minCycleTime),
        if (n.cycle != null) CycleProfileView(profile: n.cycle!),
        if (n.stepStats.isNotEmpty) StepParetoView(stats: n.stepStats),
        for (final child in n.children)
          if (child.commandTimings.isNotEmpty)
            CommandTimingView(
                moduleName: child.name, rows: child.commandTimings),
      ],
      if (configuration) ConfigEditor(app: app, node: n),
      if (diagnostics) const SizedBox(height: 8),
      if (diagnostics)
        LText('Active events', style: Theme.of(context).textTheme.titleMedium),
      if (diagnostics)
        for (final e in n.activeEvents) _eventTile(context, e),
      if (diagnostics && n.activeEvents.isEmpty)
        const ListTile(dense: true, title: LText('—')),
      if (history && n.isUnit && s.permits(GatedAction.alarmHistory))
        HistoryBrowser(node: n),
    ]);
  }

  Widget _manualPanel(BuildContext context, ModuleNode n) {
    final root = app.rootOf(n.path);
    final inManual = root?.modeActive == UnitMode.manual;
    final canManual = app.session.permits(GatedAction.manual);
    final enabled = inManual && canManual;
    final cs = Theme.of(context).colorScheme;
    // deliberately distinct from the fieldbus force: a bordered 'Manual commands'
    // card with a hand icon, on the module itself (routes THROUGH the module).
    return Card(
      color: cs.tertiaryContainer.withValues(alpha: 0.4),
      shape: RoundedRectangleBorder(
          side: BorderSide(color: cs.tertiary),
          borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Icon(Icons.pan_tool_outlined, color: cs.tertiary),
            const SizedBox(width: 8),
            LText('Manual commands',
                style: Theme.of(context).textTheme.titleMedium),
            const Spacer(),
            if (!inManual)
              const Chip(label: LText('Unit not in MANUAL'))
            else if (!canManual)
              const Chip(
                  avatar: Icon(Icons.lock_outline, size: 16),
                  label: LText('MANUAL access')),
          ]),
          const SizedBox(height: 4),
          LText('Routed through the module — interlocks still apply (§7.6.1).',
              style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: 8),
          Wrap(spacing: 8, runSpacing: 8, children: [
            for (final c in n.commands)
              FilledButton.tonal(
                // §7.6.0: a blocked manual button reveals WHY instead of being inert
                onPressed: enabled
                    ? () => _manual(context, n, c)
                    : () => app.showReleaseReportManual(
                        app.rootOf(n.path)?.path ?? '', n.path, c.value),
                child: LText(c.label),
              ),
          ]),
        ]),
      ),
    );
  }

  Future<void> _manual(
      BuildContext context, ModuleNode n, CommandInfo c) async {
    final root = app.rootOf(n.path)?.path ?? '';
    final ok = await app.repo.manualCommand(root, n.path, c.value);
    if (!ok) {
      await app.showReleaseReportManual(root, n.path, c.value);
    }
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: LText(ok
                ? 'std.manual.commandAccepted'
                : 'std.manual.commandRejected')),
      );
    }
  }

  Widget _controls(BuildContext context, ModuleNode n, AccessSession s) {
    return Row(children: [
      const Expanded(
          child: LText('Sequence and mode controls are in the mode bar.')),
      OutlinedButton.icon(
        icon: const Icon(Icons.swap_horiz),
        label: const LText('Changeover'),
        onPressed: s.permits(GatedAction.changeover)
            ? () => _changeover(context, n)
            : () => app.showReleaseReportAction(
                n.path, GatedAction.changeover, 'Changeover blocked'),
      ),
    ]);
  }

  Future<void> _changeover(BuildContext context, ModuleNode n) async {
    final ctrl = TextEditingController(text: n.modelCode);
    var selectedModel = n.availableModels.contains(n.modelCode)
        ? n.modelCode
        : (n.availableModels.isEmpty ? '' : n.availableModels.first);
    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(builder: (ctx, setDialogState) {
        return AlertDialog(
          title: const LText('Changeover — set model'),
          content: n.availableModels.isEmpty
              ? TextField(
                  controller: ctrl,
                  decoration:
                      InputDecoration(labelText: context.tr('Model code')))
              : DropdownButtonFormField<String>(
                  initialValue: selectedModel,
                  decoration:
                      InputDecoration(labelText: context.tr('Model code')),
                  items: [
                    for (final model in n.availableModels)
                      DropdownMenuItem(value: model, child: Text(model)),
                  ],
                  onChanged: (value) =>
                      setDialogState(() => selectedModel = value ?? ''),
                ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const LText('Cancel')),
            FilledButton(
              onPressed: () async {
                final model = n.availableModels.isEmpty
                    ? ctrl.text.trim()
                    : selectedModel;
                if (model.isEmpty) return;
                final modeAccepted =
                    await app.repo.setMode(n.path, UnitMode.changeover);
                final modelAccepted =
                    modeAccepted && await app.repo.setModel(n.path, model);
                final started = modelAccepted && await app.repo.start(n.path);
                if (!ctx.mounted) return;
                if (started) {
                  Navigator.pop(ctx);
                } else {
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                      content: LText('std.changeover.requestRejected')));
                }
              },
              child: const LText('Start changeover'),
            ),
          ],
        );
      }),
    );
  }

  Widget _eventTile(BuildContext context, AlarmEvent e) {
    final c = severityColor(context, e.severity);
    final dur = e.duration == null ? '' : ' · ${e.duration!.inSeconds}s';
    final st = switch (e.state) {
      AlarmState.waitReset => ' · awaiting reset',
      AlarmState.closed => ' · closed',
      _ => ''
    };
    // §8.9 rationalization join: what should the operator DO about this reason?
    final root = app.rootOf(e.sourcePath);
    AlarmMeta? meta;
    for (final m in root?.alarmMeta ?? const <AlarmMeta>[]) {
      if (m.reasonCode == e.reasonCode && e.reasonCode != 0) {
        meta = m;
        break;
      }
    }
    final active = e.state != AlarmState.closed;
    return Opacity(
      opacity: e.shelved
          ? 0.45
          : 1.0, // §8.10 de-emphasis, still listed (never hidden)
      child: ListTile(
        dense: true,
        leading: Icon(
          e.shelved
              ? Icons.notifications_paused_outlined
              : switch (e.severity) {
                  Severity.high => Icons.error,
                  Severity.medium => Icons.warning_amber,
                  Severity.low => Icons.info_outline
                },
          color: c,
        ),
        title: LText(
            '${context.tr(e.description)}${e.shelved ? '  ·  ${context.tr('SHELVED')}' : ''}'),
        subtitle: LText(
            '${e.sourcePath}${e.ioTag.isEmpty ? '' : '\n${e.ioTag}${e.ioAddress.isEmpty ? '' : ' · ${e.ioAddress}'}'}$st$dur${meta != null ? '\n→ ${context.tr(meta.operatorAction)}' : ''}'),
        isThreeLine: meta != null,
        trailing: !active || e.severity == Severity.low
            ? null
            : IconButton(
                tooltip: context.tr(e.shelved
                    ? 'Unshelve (restore annunciation)'
                    : (meta?.shelvable == true
                        ? 'Shelve annunciation (§8.10, logged; control unaffected)'
                        : 'Not shelvable — rationalize first (§8.10)')),
                icon: Icon(
                    e.shelved
                        ? Icons.notifications_active_outlined
                        : Icons.notifications_paused_outlined,
                    size: 20),
                onPressed: () => _shelve(context, e, meta),
              ),
      ),
    );
  }

  Future<void> _shelve(
      BuildContext context, AlarmEvent e, AlarmMeta? meta) async {
    final root = app.rootOf(e.sourcePath)?.path ?? '';
    if (e.shelved) {
      final ok =
          await app.repo.unshelveAlarm(root, e.sourcePath, e.description);
      if (!ok && context.mounted)
        app.showReleaseReportAction(
            root, GatedAction.alarmShelve, 'Unshelve blocked');
      return;
    }
    // act-or-explain: unrationalized/unshelvable explains instead of a dead press
    if (meta == null || !meta.shelvable) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: LText(
              'Not shelvable: this reason has no rationalization record or is flagged non-shelvable (§8.10). Safety alarms are never shelvable.')));
      return;
    }
    if (!app.session.permits(GatedAction.alarmShelve)) {
      app.showReleaseReportAction(
          root, GatedAction.alarmShelve, 'Shelve blocked');
      return;
    }
    final ok = await app.repo.shelveAlarm(
        root, e.sourcePath, e.description, const Duration(minutes: 30));
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: LText(ok
              ? 'Shelved 30 min (logged). Control is unaffected — a blocking alarm still blocks.'
              : 'Shelve refused by the PLC')));
    }
  }
}
