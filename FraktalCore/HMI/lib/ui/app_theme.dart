/// Material 3 themes: Light, Dark, High-contrast. Selection is level-gated in
/// AppState.setTheme (HMI_CONTRACT 'Tree & theming'). Event colours are fixed
/// semantics across all themes: HIGH=error, MEDIUM=amber, LOW=info blue.
library;

import 'package:flutter/material.dart';
import '../domain/types.dart';

const kThemeNames = ['Light', 'Dark', 'High contrast'];

ThemeData themeAt(int i) {
  switch (i) {
    case 1:
      return ThemeData(
          useMaterial3: true,
          colorScheme: ColorScheme.fromSeed(
              seedColor: const Color(0xFF3D6DEB), brightness: Brightness.dark));
    case 2:
      return ThemeData(
          useMaterial3: true,
          colorScheme: ColorScheme.fromSeed(
              seedColor: Colors.black,
              brightness: Brightness.light,
              contrastLevel: 1.0));
    default:
      return ThemeData(
          useMaterial3: true,
          colorScheme:
              ColorScheme.fromSeed(seedColor: const Color(0xFF3D6DEB)));
  }
}

/// Fixed severity colours (theme-aware where sensible).
Color severityColor(BuildContext ctx, Severity k) {
  switch (k) {
    case Severity.high:
      return Theme.of(ctx).colorScheme.error;
    case Severity.medium:
      return const Color(0xFFB26A00); // amber-800, AA on light+dark surfaces
    case Severity.low:
      return const Color(0xFF1565C0); // info blue
  }
}

Color stateColor(BuildContext ctx, ExecState s) {
  switch (s) {
    case ExecState.ready:
      return Colors.grey;
    case ExecState.busy:
      return const Color(0xFF2E7D32);
    case ExecState.done:
      return const Color(0xFF1565C0);
    case ExecState.error:
      return Theme.of(ctx).colorScheme.error;
    case ExecState.aborted:
      return const Color(0xFFB26A00);
  }
}
