/// Vertical mode-control bar (right side): mode selector (current-mode icon on top),
/// play/stop (run mode / graceful stop) at the bottom, and an optional step-by-step
/// toggle. Reflects §3.4.1 switch policy (prompts / blocks) and §3.4.2 run styles.
/// MANUAL shows no play/stop/step (no automatic sequence).
library;

import '../localization/localized_text.dart';
import 'package:flutter/material.dart';
import '../domain/module_node.dart';
import '../domain/types.dart';
import '../state/app_state.dart';

IconData modeIcon(UnitMode m) => switch (m) {
      UnitMode.auto => Icons.autorenew,
      UnitMode.manual => Icons.pan_tool_outlined,
      UnitMode.home => Icons.home_outlined,
      UnitMode.changeover => Icons.swap_horiz,
      UnitMode.calibration => Icons.straighten,
      UnitMode.capability => Icons.query_stats,
      UnitMode.adjustment => Icons.tune,
    };

class ModeBar extends StatelessWidget {
  final AppState app;
  const ModeBar({super.key, required this.app});

  ModuleNode? get _unit {
    final sel = app.selected;
    if (sel == null) return null;
    return sel.isUnit ? sel : app.rootOf(sel.path); // control the owning Unit
  }

  @override
  Widget build(BuildContext context) {
    final u = _unit;
    if (u == null) return const SizedBox(width: 72);
    final cs = Theme.of(context).colorScheme;
    final s = app.session;
    final canMode = s.permits(GatedAction.modeChange);
    final isManual = u.modeActive == UnitMode.manual;
    return Container(
      width: 72,
      color: cs.surfaceContainerLow,
      child: Column(children: [
        const SizedBox(height: 8),
        // ---- mode selector: current mode icon on top ----
        _modeSelector(context, u, canMode),
        const Divider(),
        const Spacer(),
        // ---- run controls (not in MANUAL: no sequence) ----
        if (!isManual) ...[
          _stepToggle(context, u, canMode),
          const SizedBox(height: 8),
          if (u.runStyle == RunStyle.holdToRun)
            _holdToRun(context, u, s)
          else if (u.runStyle == RunStyle.singleStep)
            _stepButton(context, u, s),
          const SizedBox(height: 8),
          _playStop(context, u, s),
        ],
        const SizedBox(height: 12),
      ]),
    );
  }

  Widget _modeSelector(BuildContext context, ModuleNode u, bool canMode) {
    return PopupMenuButton<UnitMode>(
      enabled: canMode,
      tooltip: context.tr('Select mode'),
      itemBuilder: (_) => [
        for (final m in u.supportedModes)
          PopupMenuItem(
              value: m,
              child: Row(children: [
                Icon(modeIcon(m), size: 18),
                const SizedBox(width: 8),
                LText(m.name.toUpperCase())
              ])),
      ],
      onSelected: (m) => _requestMode(context, u, m),
      child: Column(children: [
        Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.primaryContainer,
              borderRadius: BorderRadius.circular(12)),
          child: Icon(modeIcon(u.modeActive ?? UnitMode.auto), size: 26),
        ),
        LText((u.modeActive ?? UnitMode.auto).name.toUpperCase(),
            style: const TextStyle(fontSize: 10)),
        if (canMode) const Icon(Icons.arrow_drop_down, size: 18),
      ]),
    );
  }

  Future<void> _requestMode(
      BuildContext context, ModuleNode u, UnitMode m) async {
    if (m == u.modeActive) return;
    final policy =
        u.modePolicy[u.modeActive]; // policy of the mode being LEFT (§3.4.1)
    // BLOCKED_WHILE_RUNNING: refuse while a sequence runs
    if (u.running && policy?.shield == ModeSwitchShield.blockedWhileRunning) {
      _snack(context,
          'Stop the sequence before leaving ${u.modeActive!.name.toUpperCase()} (§3.4.1)');
      return;
    }
    // CONFIRM: prompt while running
    if (u.running && policy?.shield == ModeSwitchShield.confirm) {
      final graceful = policy?.style == ModeSwitchStyle.graceful;
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const LText('Change mode?'),
          content: LText(graceful
              ? 'A sequence is running. It will finish the current cycle, then switch to ${m.name.toUpperCase()}.'
              : 'A sequence is running. It will be interrupted immediately, then switch to ${m.name.toUpperCase()}.'),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const LText('Cancel')),
            FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child:
                    LText(graceful ? 'Finish & switch' : 'Interrupt & switch')),
          ],
        ),
      );
      if (ok != true) return;
    }
    final done = await app.repo.setMode(u.path, m);
    if (!done && context.mounted) _snack(context, 'Mode change rejected');
  }

  Widget _stepToggle(BuildContext context, ModuleNode u, bool canMode) {
    final supported = u.supportedRunStyles.length > 1; // more than CONTINUOUS
    if (!supported) return const SizedBox.shrink();
    final on = u.runStyle != RunStyle.continuous;
    return IconButton(
      tooltip: context.tr(
          on ? 'Step mode ON — tap to run continuous' : 'Enable step-by-step'),
      isSelected: on,
      icon: Icon(on ? Icons.skip_next : Icons.skip_next_outlined),
      onPressed: canMode
          ? () {
              // cycle CONTINUOUS -> SINGLE_STEP -> HOLD_TO_RUN (if supported) -> CONTINUOUS
              final order = [
                RunStyle.continuous,
                ...u.supportedRunStyles.where((r) => r != RunStyle.continuous)
              ];
              final next =
                  order[(order.indexOf(u.runStyle) + 1) % order.length];
              app.repo.setRunStyle(u.path, next);
            }
          : null,
    );
  }

  Widget _stepButton(BuildContext context, ModuleNode u, AccessSession s) {
    return FilledButton.tonal(
      onPressed: s.permits(GatedAction.startStop)
          ? () => app.repo.stepRequest(u.path)
          : () => app.showReleaseReportAction(
              u.path, GatedAction.startStop, 'Step blocked'),
      style: FilledButton.styleFrom(
          minimumSize: const Size(48, 40), padding: EdgeInsets.zero),
      child: const Icon(Icons.redo),
    );
  }

  Widget _holdToRun(BuildContext context, ModuleNode u, AccessSession s) {
    // NON-SAFETY convenience (§3.4.2): advances only while pressed.
    return GestureDetector(
      onTapDown: (_) {
        if (s.permits(GatedAction.startStop)) {
          app.repo.setHoldRun(u.path, true);
        } else {
          app.showReleaseReportAction(
              u.path, GatedAction.startStop, 'Hold-to-run blocked');
        }
      },
      onTapUp: (_) => app.repo.setHoldRun(u.path, false),
      onTapCancel: () => app.repo.setHoldRun(u.path, false),
      child: Tooltip(
        message: context.tr('Hold to run (non-safety)'),
        child: Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.tertiaryContainer,
              borderRadius: BorderRadius.circular(24)),
          child: const Icon(Icons.touch_app),
        ),
      ),
    );
  }

  Widget _playStop(BuildContext context, ModuleNode u, AccessSession s) {
    final running = u.running || u.stopPending;
    final enabled = s.permits(GatedAction.startStop) && !(u.blocking);
    // §7.8: a blocked Start stays pressable and reveals WHY (never silently no-ops)
    final startBlocked = !running && !enabled;
    void onPress() async {
      if (u.stopPending) return;
      if (running) {
        app.repo.stop(u.path);
        return;
      }
      if (!enabled) {
        app.showReleaseReportStart(u.path);
        return;
      }
      final ok = await app.repo.start(u.path);
      if (!ok)
        app.showReleaseReportStart(
            u.path); // released check failed at the PLC too
    }

    final button = Tooltip(
      message: context.tr(u.stopPending
          ? 'Stopping — finishing sequence'
          : (running
              ? 'Stop (finish sequence safely)'
              : (startBlocked ? 'Not released — tap to see why' : 'Run mode'))),
      child: IconButton.filled(
        iconSize: 30,
        // §7.8: stay pressable unless mid-stop — onPress decides act vs. explain
        onPressed: u.stopPending ? null : onPress,
        icon: Icon(running ? Icons.stop : Icons.play_arrow),
        style: IconButton.styleFrom(
          backgroundColor: running
              ? Theme.of(context).colorScheme.error
              : (startBlocked
                  ? const Color(0xFFB26A00)
                  : const Color(0xFF2E7D32)),
          foregroundColor: Colors.white,
        ),
      ),
    );
    return _Blink(active: u.stopPending, child: button);
  }

  void _snack(BuildContext context, String msg) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: LText(msg)));
}

/// Blinks its child's opacity while [active] — used for the stop button during a
/// pending graceful stop (§3.4 StopPending).
class _Blink extends StatefulWidget {
  final bool active;
  final Widget child;
  const _Blink({required this.active, required this.child});
  @override
  State<_Blink> createState() => _BlinkState();
}

class _BlinkState extends State<_Blink> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 550));
  @override
  void didUpdateWidget(covariant _Blink old) {
    super.didUpdateWidget(old);
    _sync();
  }

  @override
  void initState() {
    super.initState();
    _sync();
  }

  void _sync() {
    if (widget.active && !_c.isAnimating) _c.repeat(reverse: true);
    if (!widget.active && _c.isAnimating) {
      _c.stop();
      _c.value = 0;
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.active) return widget.child;
    return FadeTransition(
        opacity: Tween(begin: 1.0, end: 0.25).animate(_c), child: widget.child);
  }
}
