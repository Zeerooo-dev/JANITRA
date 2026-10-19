import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/sensitive_screen.dart';

class AccountCodePage extends StatefulWidget {
  const AccountCodePage({super.key, required this.grant});
  final Map<String, dynamic> grant;
  @override
  State<AccountCodePage> createState() => _AccountCodePageState();
}

class _AccountCodePageState extends State<AccountCodePage>
    with WidgetsBindingObserver {
  String? _code;
  bool _copied = false;
  @override
  void initState() {
    super.initState();
    _code = widget.grant.remove('setup_code') as String;
    final lifecycle = WidgetsBinding.instance.lifecycleState;
    if (lifecycle != null && lifecycle != AppLifecycleState.resumed) {
      _code = null;
    }
    WidgetsBinding.instance.addObserver(this);
    SensitiveScreen.enter();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed && mounted) {
      setState(() => _code = null);
    }
  }

  @override
  void dispose() {
    _code = null;
    WidgetsBinding.instance.removeObserver(this);
    SensitiveScreen.leave();
    super.dispose();
  }

  Future<void> _copyCode() async {
    final code = _code;
    if (code == null) return;
    var message = 'Code copied';
    var copied = false;
    try {
      await Clipboard.setData(ClipboardData(text: code));
      copied = true;
    } on PlatformException {
      message = 'Could not copy code. Please try again.';
    }
    if (!mounted || _code != code) return;
    setState(() => _copied = copied);
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('One-time account code')),
    body: SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Account: ${widget.grant['identifier']}',
              style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
            ),
            Text('Expires: ${widget.grant['expires_at']}'),
            const SizedBox(height: 20),
            const Text(
              'Give this one-time code directly to the person after verifying their identity. They choose their own password in Set up or recover Personnel account. A replacement code invalidates the earlier one.',
            ),
            const SizedBox(height: 20),
            if (_code != null) ...[
              Tooltip(
                message: 'Copy account code',
                child: TextButton.icon(
                  onPressed: _copyCode,
                  style: TextButton.styleFrom(
                    alignment: Alignment.centerLeft,
                    minimumSize: const Size(0, 48),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                  icon:
                      MediaQuery.disableAnimationsOf(context) ||
                          FocusManager.instance.highlightMode ==
                              FocusHighlightMode.traditional
                      ? Icon(_copied ? Icons.check : Icons.copy, size: 20)
                      : AnimatedSwitcher(
                          duration: const Duration(milliseconds: 140),
                          reverseDuration: const Duration(milliseconds: 80),
                          switchInCurve: const Cubic(0.16, 1, 0.3, 1),
                          switchOutCurve: const Cubic(0.4, 0, 1, 1),
                          child: Icon(
                            _copied ? Icons.check : Icons.copy,
                            key: ValueKey(_copied),
                            size: 20,
                          ),
                        ),
                  label: Text(_code!, style: const TextStyle(fontSize: 20)),
                ),
              ),
            ] else
              const Text(
                'The code was hidden when this screen lost focus. Issue a replacement if it was not handed over.',
              ),
            const SizedBox(height: 20),
            FilledButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Done'),
            ),
          ],
        ),
      ),
    ),
  );
}
