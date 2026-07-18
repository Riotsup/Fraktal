/// The shrinkable left tree (Core 3.13): walks the forest, expands/collapses,
/// and implements the EVENT PATH HIGHLIGHT — every ancestor from the root down
/// to the event's source tints with the subtree's highest-severity active event
/// (error > warning > info); the source node renders strongest.
library;

import '../localization/localized_text.dart';
import 'package:flutter/material.dart';
import '../domain/module_node.dart';
import '../domain/types.dart';
import '../state/app_state.dart';
import 'app_theme.dart';

class TreeMenu extends StatelessWidget {
  final AppState app;
  const TreeMenu({super.key, required this.app});

  @override
  Widget build(BuildContext context) {
    final collapsed = app.railCollapsed;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      width: collapsed ? 64 : 300,
      child: Material(
        color: Theme.of(context).colorScheme.surfaceContainerLow,
        child: Column(
          children: [
            _header(context),
            const Divider(height: 1),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.symmetric(vertical: 4),
                children: [
                  for (final root in app.visibleRoots)
                    ..._nodeTiles(context, root, 0),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _header(BuildContext context) {
    return Row(children: [
      IconButton(
        tooltip:
            context.tr(app.railCollapsed ? 'Expand menu' : 'Collapse menu'),
        icon:
            Icon(app.railCollapsed ? Icons.chevron_right : Icons.chevron_left),
        onPressed: app.toggleRail,
      ),
      if (!app.railCollapsed)
        Expanded(
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String?>(
              isExpanded: true,
              value: app.scopedRoot,
              items: [
                const DropdownMenuItem(
                    value: null, child: LText('All stations')),
                for (final r in app.forest)
                  DropdownMenuItem(
                      value: r.path,
                      child: LText(r.displayNameKey.isEmpty
                          ? r.name
                          : r.displayNameKey)),
              ],
              onChanged: app.scopeTo, // forest vs single-root scope (Core 3.1a)
            ),
          ),
        ),
    ]);
  }

  List<Widget> _nodeTiles(BuildContext context, ModuleNode n, int depth) {
    final sev = n.effectiveSeverity; // subtree max -> ancestor tint (Core 3.13)
    final own = n.ownSeverity; // the source itself -> strongest render
    final selected = app.selectedPath == n.path;
    final hasKids = n.children.isNotEmpty;
    final open = app.expanded.contains(n.path) || depth == 0;
    final cs = Theme.of(context).colorScheme;
    final tintColor = sev == null ? null : severityColor(context, sev);
    final tiles = <Widget>[
      InkWell(
        onTap: () => app.select(n.path),
        child: Container(
          height: 40,
          margin: EdgeInsets.only(
              left: app.railCollapsed ? 4 : 4.0 + depth * 14,
              right: 4,
              bottom: 2),
          decoration: BoxDecoration(
            color: own != null
                ? tintColor!.withValues(alpha: 0.28) // event SOURCE: strongest
                : sev != null
                    ? tintColor!
                        .withValues(alpha: 0.10) // ancestor on the path: tint
                    : selected
                        ? cs.secondaryContainer
                        : null,
            borderRadius: BorderRadius.circular(10),
            border: Border(
              left: BorderSide(
                width: 4,
                color:
                    tintColor ?? (selected ? cs.primary : Colors.transparent),
              ),
            ),
          ),
          child: Row(children: [
            if (hasKids)
              IconButton(
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                iconSize: 18,
                icon: Icon(open ? Icons.expand_more : Icons.chevron_right),
                onPressed: () => app.toggleExpand(n.path),
              )
            else
              const SizedBox(width: 28),
            _typeIcon(context, n, tintColor),
            if (!app.railCollapsed) ...[
              const SizedBox(width: 6),
              Expanded(
                child: LText(
                  n.displayNameKey.isEmpty ? n.name : n.displayNameKey,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontWeight: selected || own != null
                        ? FontWeight.w600
                        : FontWeight.w400,
                    color: own != null ? tintColor : null,
                  ),
                ),
              ),
              _stateDot(context, n),
              const SizedBox(width: 8),
            ],
          ]),
        ),
      ),
    ];
    if (hasKids && open) {
      for (final c in n.children.where((c) => c.tileEnable)) {
        tiles.addAll(_nodeTiles(context, c, depth + 1));
      }
    }
    return tiles;
  }

  Widget _typeIcon(BuildContext context, ModuleNode n, Color? tint) {
    final icon = switch (n.type) {
      ModuleType.unit => Icons.factory_outlined,
      ModuleType.equipmentModule => Icons.widgets_outlined,
      _ => Icons.settings_input_component_outlined,
    };
    return Icon(icon, size: 20, color: tint);
  }

  Widget _stateDot(BuildContext context, ModuleNode n) => Container(
        width: 10,
        height: 10,
        decoration: BoxDecoration(
            color: stateColor(context, n.state), shape: BoxShape.circle),
      );
}
