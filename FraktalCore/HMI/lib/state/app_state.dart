/// App-wide state (pure ChangeNotifier — no packages). Holds the forest, tree
/// selection/expansion, theme index (level-gated), and the collapsed-rail flag.
library;

import 'dart:async';
import 'package:flutter/foundation.dart';
import '../data/plc_repository.dart';
import '../domain/module_node.dart';
import '../domain/fieldbus.dart';
import '../domain/types.dart';
import '../content/module_content_controller.dart';
import '../localization/localization_controller.dart';

class HmiConfig {
  /// Theme changing is HMI-local config, gated by a minimum access level
  /// (default: open) — HMI_CONTRACT 'Tree & theming'.
  final AccessLevel themeMinLevel;
  const HmiConfig({this.themeMinLevel = AccessLevel.none});
}

class AppState extends ChangeNotifier {
  final PlcRepository repo;
  final HmiConfig config;
  final LocalizationController localization;
  final ModuleContentController content;
  factory AppState(
    PlcRepository repo, {
    HmiConfig config = const HmiConfig(),
    LocalizationController? localization,
    ModuleContentController? content,
  }) {
    final resolvedLocalization = localization ?? LocalizationController();
    return AppState._(
      repo,
      config,
      resolvedLocalization,
      content ?? ModuleContentController(localization: resolvedLocalization),
    );
  }

  AppState._(this.repo, this.config, this.localization, this.content) {
    _sub = repo.forest().listen((f) {
      final byPath = <String, ModuleNode>{};
      final duplicatePaths = <String>[];
      for (final root in f) {
        if (byPath.containsKey(root.path)) {
          duplicatePaths.add(root.path);
        } else {
          byPath[root.path] = root;
        }
      }
      if (duplicatePaths.isNotEmpty) {
        debugPrint('[Fraktal/Forest] duplicate root paths discarded: '
            '${duplicatePaths.join(', ')}');
      }
      forest = byPath.values.toList(growable: false);
      final selectionVisible = forest.any(
          (root) => selectedPath != null && root.find(selectedPath!) != null);
      if (!selectionVisible) {
        selectedPath = forest.isNotEmpty ? forest.first.path : null;
        scopedRoot = null;
        showOverview = true;
      }
      notifyListeners();
    });
    _linkSub = repo.linkState().listen((s) {
      link = s;
      notifyListeners();
    });
    _busSub = repo.fieldbus().listen((b) {
      fieldbus = b;
      notifyListeners();
    });
  }

  late final dynamic _sub;
  late final dynamic _linkSub;
  late final dynamic _busSub;
  List<BusNode> fieldbus = const [];
  bool showFieldbus = false; // Modules view vs Fieldbus view
  ReleaseReport?
      releaseReport; // §7.8 active 'why blocked' report (null = panel hidden)
  String releaseTitle = '';
  bool releaseLoading = false;
  Future<ReleaseReport> Function()?
      _releaseQuery; // re-run at a controlled rate while the panel is open
  Timer? _releaseTimer;
  bool _releaseRefreshing = false;
  LinkState link = LinkState.connecting;
  bool showOverview =
      true; // land on the plant overview (dashboard-first pattern)
  List<ModuleNode> forest = const [];
  String? selectedPath;
  String? scopedRoot; // null = show whole forest; else single-root scope (3.1a)
  final Set<String> expanded = {};
  bool railCollapsed = false;
  int themeIndex = 0; // 0 light, 1 dark, 2 high-contrast

  ModuleNode? get selected {
    for (final r in visibleRoots) {
      final hit = r.find(selectedPath ?? '');
      if (hit != null) return hit;
    }
    return null;
  }

  ModuleNode? rootOf(String path) {
    for (final r in forest) {
      if (path == r.path || path.startsWith('${r.path}.')) return r;
    }
    return null;
  }

  List<ModuleNode> get visibleRoots => scopedRoot == null
      ? forest
      : forest.where((r) => r.path == scopedRoot).toList();

  AccessSession get session =>
      rootOf(selectedPath ?? '')?.access ?? const AccessSession();

  void select(String path) {
    selectedPath = path;
    showOverview = false;
    notifyListeners();
  }

  void openOverview() {
    showOverview = true;
    showFieldbus = false;
    notifyListeners();
  }

  void setFieldbusView(bool on) {
    showFieldbus = on;
    showOverview = false;
    notifyListeners();
  }

  /// §7.8 — surface why an action is blocked (persistent panel). Pure query.
  Future<void> showReleaseReportStart(String unitPath) async {
    await _showReleaseReport(
      title: 'std.release.startBlocked',
      query: () => repo.releaseReportStart(unitPath),
    );
  }

  Future<void> showReleaseReportManual(
      String unitPath, String targetPath, int commandValue) async {
    await _showReleaseReport(
      title: 'std.release.manualBlocked',
      query: () => repo.releaseReportManual(unitPath, targetPath, commandValue),
    );
  }

  Future<void> showReleaseReportAction(
      String unitPath, GatedAction action, String title) async {
    await _showReleaseReport(
      title: title,
      query: () => repo.releaseReportAction(unitPath, action),
    );
  }

  bool get releasePanelVisible => _releaseQuery != null;

  Future<void> _showReleaseReport({
    required String title,
    required Future<ReleaseReport> Function() query,
  }) async {
    _releaseTimer?.cancel();
    _releaseQuery = query;
    releaseTitle = title;
    releaseReport = null;
    releaseLoading = true;
    notifyListeners();
    await _refreshRelease();
    if (identical(_releaseQuery, query)) {
      _releaseTimer = Timer.periodic(
        const Duration(seconds: 2),
        (_) => _refreshRelease(),
      );
    }
  }

  /// §7.8 — keep the panel live without coupling a mailbox query to every
  /// repository snapshot. OPC UA query acknowledgements themselves publish a
  /// snapshot, so snapshot-driven re-querying creates an unbounded feedback loop.
  Future<void> _refreshRelease() async {
    if (_releaseQuery == null || _releaseRefreshing) return;
    final query = _releaseQuery!;
    _releaseRefreshing = true;
    try {
      final r = await query();
      if (identical(_releaseQuery, query)) {
        releaseReport = r;
        releaseLoading = false;
        notifyListeners();
      }
    } on Object {
      if (identical(_releaseQuery, query)) {
        releaseReport = const ReleaseReport(false, [
          ReleaseReason('std.release.transportUnavailable', ReleaseKind.other),
        ]);
        releaseLoading = false;
        notifyListeners();
      }
    } finally {
      _releaseRefreshing = false;
    }
  }

  void clearRelease() {
    _releaseTimer?.cancel();
    _releaseTimer = null;
    releaseReport = null;
    _releaseQuery = null;
    releaseLoading = false;
    notifyListeners();
  }

  /// All active events across the forest, worst-first — for the global banner.
  List<AlarmEvent> get allActiveEvents {
    final out = <AlarmEvent>[];
    void walk(ModuleNode n) {
      out.addAll(n.activeEvents.where((e) => e.state != AlarmState.closed));
      for (final c in n.children) walk(c);
    }

    for (final r in forest) walk(r);
    out.sort((a, b) => b.severity.index - a.severity.index);
    return out;
  }

  void toggleExpand(String path) {
    expanded.contains(path) ? expanded.remove(path) : expanded.add(path);
    notifyListeners();
  }

  void toggleRail() {
    railCollapsed = !railCollapsed;
    notifyListeners();
  }

  void scopeTo(String? rootPath) {
    scopedRoot = rootPath;
    notifyListeners();
  }

  /// Level-gated theme change (returns false when the session is insufficient).
  bool setTheme(int i) {
    if (session.level.index < config.themeMinLevel.index) return false;
    themeIndex = i;
    notifyListeners();
    return true;
  }

  @override
  void dispose() {
    _releaseTimer?.cancel();
    _sub.cancel();
    _linkSub.cancel();
    _busSub.cancel();
    repo.dispose();
    super.dispose();
  }
}
