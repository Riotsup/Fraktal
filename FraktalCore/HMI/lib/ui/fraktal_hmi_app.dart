library;

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import '../state/app_state.dart';
import '../localization/default_catalogs.dart';
import '../localization/localized_text.dart';
import 'app_theme.dart';
import 'shell.dart';

class FraktalHmiApp extends StatelessWidget {
  final AppState app;
  final VoidCallback? onEditUnitSelection;
  final ValueChanged<String>? onLanguageChanged;
  const FraktalHmiApp({
    super.key,
    required this.app,
    this.onEditUnitSelection,
    this.onLanguageChanged,
  });

  @override
  Widget build(BuildContext context) {
    return LocalizationScope(
      controller: app.localization,
      child: ListenableBuilder(
        listenable: Listenable.merge([app, app.localization, app.content]),
        builder: (context, _) => MaterialApp(
          title: app.localization.resolve('std.app.title'),
          debugShowCheckedModeBanner: false,
          theme: themeAt(app.themeIndex),
          locale: app.localization.locale,
          supportedLocales: [
            for (final code in availableLanguages.keys) Locale(code),
          ],
          localizationsDelegates: const [
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          home: Shell(
            app: app,
            onEditUnitSelection: onEditUnitSelection,
            onLanguageChanged: onLanguageChanged,
          ),
        ),
      ),
    );
  }
}
