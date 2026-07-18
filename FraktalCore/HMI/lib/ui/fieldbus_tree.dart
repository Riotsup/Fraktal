/// Fieldbus topology tree (Core §10.5.1 / §3.13): the physical bus beside the
/// logical module tree. Nodes coloured by state (worst-in-subtree tints ancestors,
/// like the module tree); channels show live values — digital on/off, analog
/// value+unit. Read/diagnostic; forcing would be a §7.6/§7.7-gated action.
library;

import '../localization/localized_text.dart';
import 'package:flutter/material.dart';
import '../domain/fieldbus.dart';
import '../domain/types.dart';
import '../state/app_state.dart';

Color nodeStateColor(BuildContext ctx, NodeState s) {
  switch (s) {
    case NodeState.operational:
      return const Color(0xFF2E7D32);
    case NodeState.safeop:
    case NodeState.preop:
    case NodeState.init:
      return const Color(0xFFB26A00); // degraded -> warning
    case NodeState.offline:
    case NodeState.fault:
      return Theme.of(ctx).colorScheme.error;
  }
}

String nodeStateLabel(NodeState s) => switch (s) {
      NodeState.operational => 'OP',
      NodeState.safeop => 'SAFEOP',
      NodeState.preop => 'PREOP',
      NodeState.init => 'INIT',
      NodeState.offline => 'OFFLINE',
      NodeState.fault => 'FAULT',
    };

class FieldbusTree extends StatefulWidget {
  final AppState app;
  const FieldbusTree({super.key, required this.app});
  @override
  State<FieldbusTree> createState() => _FieldbusTreeState();
}

class _FieldbusTreeState extends State<FieldbusTree> {
  final Set<String> _expanded = {};
  BusNode? _selected;

  @override
  Widget build(BuildContext context) {
    final roots = widget.app.fieldbus;
    if (roots.isEmpty) {
      return const Center(
          child: Padding(
              padding: EdgeInsets.all(24),
              child: LText(
                  'No fieldbus diagnostics available on this transport.')));
    }
    BusNode? mappingFault;
    for (final root in roots) {
      if (!root.mappingValid) {
        mappingFault = root;
        break;
      }
    }
    return Column(children: [
      if (mappingFault != null)
        Container(
          width: double.infinity,
          color: Theme.of(context).colorScheme.errorContainer,
          padding: const EdgeInsets.all(12),
          child: LText(
            mappingFault.mappingDiagnosticKey.isEmpty
                ? 'std.error.fieldbusMappingInvalid'
                : mappingFault.mappingDiagnosticKey,
            style: TextStyle(
                color: Theme.of(context).colorScheme.onErrorContainer,
                fontWeight: FontWeight.w700),
          ),
        ),
      Expanded(
        child: Row(children: [
          SizedBox(
            width: 340,
            child: Material(
              color: Theme.of(context).colorScheme.surfaceContainerLow,
              child: ListView(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  children: [
                    for (final n in roots) ..._nodeTiles(context, n, 0),
                  ]),
            ),
          ),
          const VerticalDivider(width: 1),
          Expanded(child: _channelPanel(context)),
        ]),
      ),
    ]);
  }

  List<Widget> _nodeTiles(BuildContext context, BusNode n, int depth) {
    final eff = n.effectiveState;
    final tint = nodeStateColor(context, eff);
    final ownBad = n.state != NodeState.operational;
    final open = _expanded.contains(n.name) || depth == 0;
    final selected = _selected?.name == n.name;
    final tiles = <Widget>[
      InkWell(
        onTap: () => setState(() => _selected = n),
        child: Container(
          height: 40,
          margin: EdgeInsets.only(left: 4.0 + depth * 14, right: 4, bottom: 2),
          decoration: BoxDecoration(
            color: ownBad
                ? tint.withValues(alpha: 0.20)
                : (selected
                    ? Theme.of(context).colorScheme.secondaryContainer
                    : null),
            borderRadius: BorderRadius.circular(10),
            border: Border(
                left: BorderSide(
                    width: 4,
                    color: eff == NodeState.operational
                        ? (selected
                            ? Theme.of(context).colorScheme.primary
                            : Colors.transparent)
                        : tint)),
          ),
          child: Row(children: [
            if (n.children.isNotEmpty)
              IconButton(
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                iconSize: 18,
                icon: Icon(open ? Icons.expand_more : Icons.chevron_right),
                onPressed: () => setState(() =>
                    open ? _expanded.remove(n.name) : _expanded.add(n.name)),
              )
            else
              const SizedBox(width: 28),
            Icon(n.children.isEmpty ? Icons.memory : Icons.hub_outlined,
                size: 20, color: eff == NodeState.operational ? null : tint),
            const SizedBox(width: 6),
            Expanded(
                child: LText(n.name,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        fontWeight:
                            ownBad ? FontWeight.w600 : FontWeight.w400))),
            if (!n.linkOk)
              Icon(Icons.link_off,
                  size: 16, color: Theme.of(context).colorScheme.error),
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 6),
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                  color: tint.withValues(alpha: 0.16),
                  borderRadius: BorderRadius.circular(6)),
              child: LText(nodeStateLabel(n.state),
                  style: TextStyle(
                      fontSize: 11, color: tint, fontWeight: FontWeight.w600)),
            ),
          ]),
        ),
      ),
    ];
    if (n.children.isNotEmpty && open) {
      for (final c in n.children) {
        tiles.addAll(_nodeTiles(context, c, depth + 1));
      }
    }
    return tiles;
  }

  Widget _channelPanel(BuildContext context) {
    final n = _selected;
    if (n == null)
      return const Center(child: LText('Select a node to see its I/O'));
    if (n.channels.isEmpty)
      return Center(
          child: LText('${n.name} — ${n.typeId}\nNo channels (coupler/master)',
              textAlign: TextAlign.center));
    return ListView(padding: const EdgeInsets.all(16), children: [
      LText('${n.name}  ·  ${n.typeId}',
          style: Theme.of(context).textTheme.titleMedium),
      if (n.descriptionKey.isNotEmpty) LText(n.descriptionKey),
      LText(
          '${n.address}  ·  ${nodeStateLabel(n.state)}${n.linkOk ? '' : '  ·  LINK DOWN'}',
          style: TextStyle(color: nodeStateColor(context, n.state))),
      const Divider(),
      for (final c in n.channels) _channelTile(context, c),
    ]);
  }

  Widget _channelTile(BuildContext context, IoChannel c) {
    final isOut = c.dir == ChannelDir.output;
    Widget value;
    if (c.kind == ChannelKind.digital) {
      value = Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
        decoration: BoxDecoration(
          color: c.boolValue
              ? const Color(0xFF2E7D32)
              : Theme.of(context).colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(6),
        ),
        child: LText(c.boolValue ? 'ON' : 'OFF',
            style: TextStyle(
                color: c.boolValue ? Colors.white : null,
                fontWeight: FontWeight.w600)),
      );
    } else {
      value = LText('${c.analogValue.toStringAsFixed(2)} ${c.unit}',
          style: Theme.of(context).textTheme.titleMedium);
    }
    final isOutput = c.dir == ChannelDir.output;
    final canForce = isOutput && widget.app.session.permits(GatedAction.manual);
    return ListTile(
      dense: true,
      leading: Icon(
        isOut ? Icons.output : Icons.input,
        color: c.forced
            ? const Color(0xFFB26A00)
            : (c.quality && !c.faultActive
                ? null
                : Theme.of(context).colorScheme.error),
      ),
      title: Text(c.name,
          style: TextStyle(
              fontFamily: 'monospace',
              fontWeight: c.faultActive ? FontWeight.w700 : FontWeight.w500,
              color:
                  c.faultActive ? Theme.of(context).colorScheme.error : null)),
      subtitle: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        if (c.descriptionKey.isNotEmpty) LText(c.descriptionKey),
        if (c.faultActive && c.diagnosticKey.isNotEmpty)
          LText(c.diagnosticKey,
              style: TextStyle(
                  color: Theme.of(context).colorScheme.error,
                  fontWeight: FontWeight.w600)),
        LText(
            '${c.address.isEmpty ? '' : '${c.address}  ·  '}${c.path}  ·  ${c.dir.name} ${c.kind.name}${c.forced ? ' · FORCED' : ''}${c.quality ? '' : ' · BAD QUALITY'}'),
      ]),
      trailing: Row(mainAxisSize: MainAxisSize.min, children: [
        value,
        if (c.modulePath.isNotEmpty)
          IconButton(
            tooltip: context.tr('std.fieldbus.openModule'),
            icon: const Icon(Icons.open_in_new, size: 18),
            onPressed: () {
              widget.app.select(c.modulePath);
              widget.app.setFieldbusView(false);
            },
          ),
        if (canForce)
          IconButton(
            tooltip: context
                .tr(c.forced ? 'Clear force' : 'Force (§7.6/§7.7, logged)'),
            icon: Icon(c.forced ? Icons.lock_open : Icons.push_pin_outlined,
                color: c.forced ? const Color(0xFFB26A00) : null),
            onPressed: () => _force(context, c),
          )
        else if (isOutput)
          IconButton(
            tooltip: context.tr('Why can\'t I force this?'),
            icon: const Icon(Icons.lock_outline, size: 18),
            onPressed: () => ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                    content: LText(
                        'Forcing an output requires MANUAL access level (§7.7). Log in with sufficient rights.'))),
          ),
        // inputs are read-only: no force control (output-only rule, §10.5.1)
      ]),
    );
  }

  Future<void> _force(BuildContext context, IoChannel c) async {
    final root = widget.app.rootOf(c.path)?.path ??
        (widget.app.forest.isNotEmpty ? widget.app.forest.first.path : '');
    if (c.forced) {
      final ok = await widget.app.repo.forceChannel(root, c.path, force: false);
      if (context.mounted) _snack(context, ok ? 'Force cleared' : 'Denied');
      return;
    }
    bool boolVal = !c.boolValue;
    final analogCtrl =
        TextEditingController(text: c.analogValue.toStringAsFixed(2));
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: LText('Force ${c.name}'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          LText(
              'Forcing overrides the live process image. Logged manual action (§7.6/§7.7).',
              style: Theme.of(ctx).textTheme.bodySmall),
          const SizedBox(height: 12),
          if (c.kind == ChannelKind.digital)
            StatefulBuilder(
                builder: (_, set) => SwitchListTile(
                    title: LText('Force value: ${boolVal ? 'ON' : 'OFF'}'),
                    value: boolVal,
                    onChanged: (v) => set(() => boolVal = v)))
          else
            TextField(
                controller: analogCtrl,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                    labelText: context.tr('Force value'), suffixText: c.unit)),
        ]),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const LText('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const LText('Force')),
        ],
      ),
    );
    if (confirmed != true) return;
    final ok = await widget.app.repo.forceChannel(root, c.path,
        force: true,
        boolValue: boolVal,
        analogValue: double.tryParse(analogCtrl.text) ?? 0);
    if (context.mounted)
      _snack(context,
          ok ? 'Channel forced (logged)' : 'Denied — insufficient access');
  }

  void _snack(BuildContext context, String msg) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: LText(msg)));
}
