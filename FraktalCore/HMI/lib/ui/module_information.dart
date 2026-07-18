library;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:pdfrx/pdfrx.dart';
import '../content/module_content_controller.dart';
import '../domain/module_node.dart';
import '../domain/types.dart';
import '../localization/localized_text.dart';
import '../state/app_state.dart';

class ModuleInformationCard extends StatelessWidget {
  final AppState app;
  final ModuleNode node;
  const ModuleInformationCard({
    super.key,
    required this.app,
    required this.node,
  });

  @override
  Widget build(BuildContext context) {
    final session = app.session;
    if (!app.content
        .permits(node.path, ModuleSection.information, session.level)) {
      return const SizedBox.shrink();
    }
    final description = node.descriptionKey.isEmpty
        ? 'std.module.noDescription'
        : node.descriptionKey;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            const Icon(Icons.info_outline),
            const SizedBox(width: 8),
            LText('std.module.info',
                style: Theme.of(context).textTheme.titleMedium),
            const Spacer(),
            if (session.level == AccessLevel.admin)
              IconButton(
                key: const Key('edit-section-access'),
                tooltip: context.tr('std.module.sectionAccess'),
                onPressed: () => showSectionAccessDialog(context, app, node),
                icon: const Icon(Icons.admin_panel_settings_outlined),
              ),
          ]),
          LText(description),
        ]),
      ),
    );
  }
}

class ModuleDocumentsCard extends StatelessWidget {
  final AppState app;
  final ModuleNode node;
  const ModuleDocumentsCard({
    super.key,
    required this.app,
    required this.node,
  });

  @override
  Widget build(BuildContext context) {
    final session = app.session;
    if (!app.content
        .permits(node.path, ModuleSection.documentation, session.level)) {
      return const SizedBox.shrink();
    }
    final documents = app.content.documentsFor(node.path);
    final canUpload = session.level.index >= AccessLevel.engineer.index;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            const Icon(Icons.picture_as_pdf_outlined),
            const SizedBox(width: 8),
            LText('std.module.documents',
                style: Theme.of(context).textTheme.titleMedium),
            const Spacer(),
            if (canUpload)
              FilledButton.tonalIcon(
                key: const Key('upload-module-pdf'),
                onPressed: () => _upload(context, session),
                icon: const Icon(Icons.upload_file),
                label: const LText('std.module.uploadPdf'),
              ),
          ]),
          if (documents.isEmpty)
            const ListTile(
              dense: true,
              title: LText('std.module.noDocuments'),
            )
          else
            for (final document in documents)
              ListTile(
                leading: const Icon(Icons.picture_as_pdf),
                title: LText(document.titleKey),
                subtitle: LText(_documentMetadata(context, document)),
                onTap: () => _open(context, document),
                trailing: session.level == AccessLevel.admin
                    ? IconButton(
                        tooltip: context.tr('std.common.delete'),
                        onPressed: () => app.content.removeDocument(document),
                        icon: const Icon(Icons.delete_outline),
                      )
                    : null,
              ),
        ]),
      ),
    );
  }

  Future<void> _upload(BuildContext context, AccessSession session) async {
    final picked = await FilePicker.pickFiles(
      dialogTitle: context.tr('std.module.uploadPdf'),
      type: FileType.custom,
      allowedExtensions: const ['pdf'],
      withData: true,
    );
    final file = picked?.files.single;
    if (file?.bytes == null || !context.mounted) return;
    final title = TextEditingController(
        text: file!.name
            .replaceFirst(RegExp(r'\.pdf$', caseSensitive: false), ''));
    final accepted = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const LText('std.module.uploadPdf'),
        content: TextField(
          controller: title,
          decoration: InputDecoration(
            labelText: context.tr('std.module.documentTitle'),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const LText('std.common.cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const LText('std.common.save'),
          ),
        ],
      ),
    );
    if (accepted != true) return;
    try {
      await app.content.addPdf(
        modulePath: node.path,
        fileName: file.name,
        bytes: file.bytes!,
        title: title.text,
        uploadedBy: session.user,
      );
    } on FormatException catch (error) {
      if (!context.mounted) return;
      final key = error.message == 'PDF too large'
          ? 'std.module.pdfTooLarge'
          : 'std.module.pdfOnly';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: LText(key)),
      );
    }
  }

  Future<void> _open(BuildContext context, ModuleDocument document) =>
      Navigator.of(context).push(MaterialPageRoute(
        builder: (context) => Scaffold(
          appBar: AppBar(title: LText(document.titleKey)),
          body: PdfViewer.data(document.bytes, sourceName: document.fileName),
        ),
      ));
}

String _documentMetadata(BuildContext context, ModuleDocument document) {
  final local = document.uploadedAt.toLocal();
  final material = MaterialLocalizations.of(context);
  final date = material.formatMediumDate(local);
  final time = material.formatTimeOfDay(TimeOfDay.fromDateTime(local));
  return '${document.fileName} · ${document.uploadedBy} · $date $time';
}

Future<void> showSectionAccessDialog(
    BuildContext context, AppState app, ModuleNode node) async {
  await showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      title: const LText('std.module.sectionAccess'),
      content: SizedBox(
        width: 560,
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const LText('std.module.sectionAccessHelp'),
          const SizedBox(height: 12),
          for (final section in ModuleSection.values)
            ListTile(
              title: LText(_sectionKey(section)),
              trailing: DropdownButton<AccessLevel>(
                value: app.content.requiredLevel(node.path, section),
                items: [
                  for (final level in AccessLevel.values)
                    DropdownMenuItem(
                      value: level,
                      child: LText(_levelKey(level)),
                    ),
                ],
                onChanged: (level) {
                  if (level != null) {
                    app.content.setRequiredLevel(node.path, section, level);
                  }
                },
              ),
            ),
        ]),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const LText('std.common.close'),
        ),
      ],
    ),
  );
}

String _sectionKey(ModuleSection section) => switch (section) {
      ModuleSection.information => 'std.module.infoSection',
      ModuleSection.operations => 'std.module.operationsSection',
      ModuleSection.diagnostics => 'std.module.diagnosticsSection',
      ModuleSection.configuration => 'std.module.configurationSection',
      ModuleSection.documentation => 'std.module.documentationSection',
      ModuleSection.history => 'std.module.historySection',
    };

String _levelKey(AccessLevel level) => 'std.access.${level.name}';
