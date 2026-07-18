/// Data-driven login per HMI_CONTRACT / Core 7.7(c): the repository writes
/// ReqUser/ReqSecret and pulses ReqLogin on the PLC; the PLC clears the secret.
library;

import 'package:flutter/material.dart';

import '../localization/localized_text.dart';
import '../state/app_state.dart';

Future<void> showLoginDialog(BuildContext context, AppState app) async {
  final loggedIn = await showDialog<bool>(
    context: context,
    builder: (_) => _LoginDialog(app: app),
  );
  if (loggedIn == true && context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: LText('std.login.success')),
    );
  }
}

class _LoginDialog extends StatefulWidget {
  final AppState app;
  const _LoginDialog({required this.app});

  @override
  State<_LoginDialog> createState() => _LoginDialogState();
}

class _LoginDialogState extends State<_LoginDialog> {
  final _user = TextEditingController();
  final _pin = TextEditingController();
  final _pinFocus = FocusNode();
  bool _busy = false;
  String? _errorKey;

  @override
  void dispose() {
    _user.dispose();
    _pin.dispose();
    _pinFocus.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_busy) return;
    final user = _user.text.trim();
    if (user.isEmpty || _pin.text.isEmpty) {
      setState(() => _errorKey = 'std.login.required');
      return;
    }
    setState(() {
      _busy = true;
      _errorKey = null;
    });
    try {
      final root = widget.app.rootOf(widget.app.selectedPath ?? '')?.path ??
          widget.app.forest.first.path;
      final ok = await widget.app.repo.login(root, user, _pin.text);
      if (!mounted) return;
      if (ok) {
        Navigator.pop(context, true);
      } else {
        _pin.clear();
        setState(() {
          _busy = false;
          _errorKey = 'std.login.failedDetail';
        });
        _pinFocus.requestFocus();
      }
    } on Object {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _errorKey = 'std.login.unavailable';
      });
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: const LText('std.login.title'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(
            key: const Key('login-user'),
            controller: _user,
            enabled: !_busy,
            autofocus: true,
            textInputAction: TextInputAction.next,
            autofillHints: const [AutofillHints.username],
            onSubmitted: (_) => _pinFocus.requestFocus(),
            decoration:
                InputDecoration(labelText: context.tr('std.login.user')),
          ),
          TextField(
            key: const Key('login-pin'),
            controller: _pin,
            focusNode: _pinFocus,
            enabled: !_busy,
            obscureText: true,
            textInputAction: TextInputAction.done,
            autofillHints: const [AutofillHints.password],
            onSubmitted: (_) => _submit(),
            decoration: InputDecoration(labelText: context.tr('std.login.pin')),
          ),
          if (_errorKey != null) ...[
            const SizedBox(height: 12),
            Semantics(
              liveRegion: true,
              child: Row(
                key: const Key('login-error'),
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.error_outline,
                      size: 20, color: Theme.of(context).colorScheme.error),
                  const SizedBox(width: 8),
                  Expanded(
                    child: LText(
                      _errorKey!,
                      style:
                          TextStyle(color: Theme.of(context).colorScheme.error),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ]),
        actions: [
          TextButton(
            onPressed: _busy ? null : () => Navigator.pop(context, false),
            child: const LText('Cancel'),
          ),
          FilledButton(
            key: const Key('login-submit'),
            onPressed: _busy ? null : _submit,
            child: _busy
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const LText('std.login.title'),
          ),
        ],
      );
}
