library;

import 'dart:convert';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import '../localization/catalog_csv.dart';
import '../localization/default_catalogs.dart';
import '../localization/localization_controller.dart';
import '../localization/localized_text.dart';

class FirstLanguageSelection extends StatefulWidget {
  final LocalizationController controller;
  final Set<String> initialEnabled;
  final String initialActive;
  final void Function(Set<String> enabled, String active) onContinue;

  const FirstLanguageSelection({
    super.key,
    required this.controller,
    required this.initialEnabled,
    required this.initialActive,
    required this.onContinue,
  });

  @override
  State<FirstLanguageSelection> createState() => _FirstLanguageSelectionState();
}

class _FirstLanguageSelectionState extends State<FirstLanguageSelection> {
  late final Set<String> _enabled;
  late String _active;

  @override
  void initState() {
    super.initState();
    _enabled = Set.of(widget.initialEnabled);
    if (_enabled.isEmpty) _enabled.add(widget.initialActive);
    _active = _enabled.contains(widget.initialActive)
        ? widget.initialActive
        : _enabled.first;
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        body: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 640),
                child: Card(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Icon(Icons.translate,
                            size: 52,
                            color: Theme.of(context).colorScheme.primary),
                        const SizedBox(height: 12),
                        LText('std.languages.firstTitle',
                            textAlign: TextAlign.center,
                            style: Theme.of(context).textTheme.headlineSmall),
                        const SizedBox(height: 8),
                        const LText('std.languages.firstHelp',
                            textAlign: TextAlign.center),
                        const SizedBox(height: 20),
                        for (final language in availableLanguages.entries)
                          CheckboxListTile(
                            value: _enabled.contains(language.key),
                            title: LText(language.value),
                            subtitle: LText(language.key),
                            onChanged: (checked) => setState(() {
                              if (checked == true) {
                                _enabled.add(language.key);
                              } else if (_enabled.length > 1) {
                                _enabled.remove(language.key);
                                if (_active == language.key) {
                                  _active = _enabled.first;
                                }
                              }
                            }),
                          ),
                        const SizedBox(height: 12),
                        DropdownButtonFormField<String>(
                          initialValue: _active,
                          decoration: InputDecoration(
                            labelText: context.tr('std.languages.active'),
                            border: const OutlineInputBorder(),
                          ),
                          items: [
                            for (final code in _enabled)
                              DropdownMenuItem(
                                  value: code,
                                  child:
                                      LText(availableLanguages[code] ?? code)),
                          ],
                          onChanged: (value) =>
                              setState(() => _active = value ?? _active),
                        ),
                        const SizedBox(height: 20),
                        FilledButton.icon(
                          key: const Key('save-language-selection'),
                          onPressed: () {
                            widget.controller
                                .configure(enabled: _enabled, active: _active);
                            widget.onContinue(Set.of(_enabled), _active);
                          },
                          icon: const Icon(Icons.arrow_forward),
                          label: const LText('std.languages.continue'),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
}

Future<void> showLanguageSettings(
    BuildContext context, LocalizationController controller) async {
  await showDialog<void>(
    context: context,
    builder: (context) => _LanguageSettingsDialog(controller: controller),
  );
}

class _LanguageSettingsDialog extends StatefulWidget {
  final LocalizationController controller;
  const _LanguageSettingsDialog({required this.controller});

  @override
  State<_LanguageSettingsDialog> createState() =>
      _LanguageSettingsDialogState();
}

class _LanguageSettingsDialogState extends State<_LanguageSettingsDialog> {
  late String _language = widget.controller.activeLanguage;
  String? _status;

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: const LText('std.languages.settings'),
        content: SizedBox(
          width: 620,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const LText('std.languages.catalogHelp'),
            const SizedBox(height: 16),
            DropdownButtonFormField<String>(
              initialValue: _language,
              decoration: InputDecoration(
                labelText: context.tr('std.common.language'),
                border: const OutlineInputBorder(),
              ),
              items: [
                for (final code in widget.controller.enabledLanguages)
                  DropdownMenuItem(
                      value: code,
                      child: LText(availableLanguages[code] ?? code)),
              ],
              onChanged: (value) =>
                  setState(() => _language = value ?? _language),
            ),
            const SizedBox(height: 16),
            _catalogRow(CatalogScope.standard, 'std.languages.standardCatalog'),
            _catalogRow(CatalogScope.project, 'std.languages.projectCatalog'),
            if (_status != null) ...[
              const SizedBox(height: 8),
              LText(_status!, key: const Key('language-catalog-status')),
            ],
          ]),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const LText('std.common.close'),
          ),
        ],
      );

  Widget _catalogRow(CatalogScope scope, String label) => ListTile(
        title: LText(label),
        trailing: Wrap(spacing: 8, children: [
          OutlinedButton.icon(
            onPressed: () => _import(scope),
            icon: const Icon(Icons.file_upload_outlined),
            label: const LText('std.common.import'),
          ),
          OutlinedButton.icon(
            onPressed: () => _export(scope),
            icon: const Icon(Icons.file_download_outlined),
            label: const LText('std.common.export'),
          ),
        ]),
      );

  Future<void> _import(CatalogScope scope) async {
    final picked = await FilePicker.pickFiles(
      dialogTitle: context.tr('std.common.import'),
      type: FileType.custom,
      allowedExtensions: const ['csv'],
      withData: true,
    );
    final bytes = picked?.files.single.bytes;
    if (bytes == null) return;
    try {
      await widget.controller.importCsv(
          scope, _language, utf8.decode(bytes, allowMalformed: false));
      if (mounted) setState(() => _status = 'std.error.catalogImported');
    } on Object {
      if (mounted) setState(() => _status = 'std.error.catalogInvalid');
    }
  }

  Future<void> _export(CatalogScope scope) => FilePicker.saveFile(
        dialogTitle: context.tr('std.common.export'),
        fileName: 'fraktal_${scope.name}_$_language.csv',
        type: FileType.custom,
        allowedExtensions: const ['csv'],
        bytes: utf8.encode(widget.controller.exportCsv(scope, _language)),
      );
}
