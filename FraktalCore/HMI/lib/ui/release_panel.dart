/// §7.8 release panel — a persistent bottom strip that shows WHY the current
/// action is blocked: the full rollup (mode, access, alarm, interlock reasons),
/// each with its description. Stays visible while blocked; a Dismiss clears it.
library;

import '../localization/localized_text.dart';
import 'package:flutter/material.dart';
import '../domain/types.dart';
import '../state/app_state.dart';

class ReleasePanel extends StatelessWidget {
  final AppState app;
  const ReleasePanel({super.key, required this.app});

  @override
  Widget build(BuildContext context) {
    if (!app.releasePanelVisible) return const SizedBox.shrink();
    final r = app.releaseReport;
    final cs = Theme.of(context).colorScheme;
    if (app.releaseLoading || r == null) {
      return Material(
        color: cs.secondaryContainer,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 8, 10),
          child: Row(children: [
            const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2.5),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: LText(
                'std.release.checking',
                style: Theme.of(context)
                    .textTheme
                    .titleMedium
                    ?.copyWith(fontWeight: FontWeight.w600),
              ),
            ),
            IconButton(
              icon: const Icon(Icons.close),
              onPressed: app.clearRelease,
              tooltip: context.tr('Dismiss'),
            ),
          ]),
        ),
      );
    }
    // released -> green 'now clear' confirmation; blocked -> error-tinted list
    final clear = r.released;
    return Material(
      color: clear ? const Color(0xFFC8E6C9) : cs.errorContainer,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
        child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                Icon(clear ? Icons.check_circle : Icons.block,
                    color: clear ? const Color(0xFF2E7D32) : cs.error),
                const SizedBox(width: 8),
                LText(
                    clear ? 'Now released — you can proceed' : app.releaseTitle,
                    style: Theme.of(context)
                        .textTheme
                        .titleMedium
                        ?.copyWith(fontWeight: FontWeight.w600)),
                const Spacer(),
                IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: app.clearRelease,
                    tooltip: context.tr('Dismiss')),
              ]),
              if (!clear)
                Wrap(spacing: 8, runSpacing: 8, children: [
                  if (r.reasons.isEmpty)
                    _reasonChip(
                      context,
                      const ReleaseReason(
                        'std.release.noDetails',
                        ReleaseKind.other,
                      ),
                    )
                  else
                    for (final reason in r.reasons)
                      _reasonChip(context, reason),
                ]),
            ]),
      ),
    );
  }

  Widget _reasonChip(BuildContext context, ReleaseReason reason) {
    final icon = switch (reason.kind) {
      ReleaseKind.mode => Icons.tune,
      ReleaseKind.access => Icons.lock_outline,
      ReleaseKind.alarm => Icons.notification_important_outlined,
      ReleaseKind.interlock => Icons.link_off,
      ReleaseKind.other => Icons.info_outline,
    };
    final owner = reason.sourcePath.isEmpty ? '' : '${reason.sourcePath}: ';
    final code = reason.reasonCode == 0 ? '' : ' (#${reason.reasonCode})';
    return Chip(
      avatar: Icon(icon, size: 18),
      label: Text(owner +
          context.tr(reason.description) +
          code +
          (reason.bypassable ? context.tr(' (bypassable)') : '')),
      backgroundColor: Theme.of(context).colorScheme.surface,
    );
  }
}
