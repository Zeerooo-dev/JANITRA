import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/sensitive_screen.dart';
import '../../core/secret_text_form_field.dart';

class AccountSetupPage extends StatefulWidget {
  const AccountSetupPage({super.key, required this.client});
  final SupabaseClient client;
  @override
  State<AccountSetupPage> createState() => _AccountSetupPageState();
}

class _AccountSetupPageState extends State<AccountSetupPage>
    with WidgetsBindingObserver {
  final _form = GlobalKey<FormState>();
  final _identifier = TextEditingController(),
      _code = TextEditingController(),
      _password = TextEditingController(),
      _confirm = TextEditingController();
  bool _busy = false, _completed = false;
  String? _error;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    SensitiveScreen.enter();
  }

  void _clearSecrets() {
    _code.clear();
    _password.clear();
    _confirm.clear();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) _clearSecrets();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _clearSecrets();
    _identifier.dispose();
    _code.dispose();
    _password.dispose();
    _confirm.dispose();
    SensitiveScreen.leave();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_busy || !_form.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final result = await widget.client.functions.invoke(
        'personnel-auth',
        body: {
          'action': 'redeem',
          'identifier': _identifier.text.trim(),
          'code': _code.text.trim(),
          'password': _password.text,
        },
      );
      if (result.data is! Map || result.data['completed'] != true) {
        throw const FormatException('No confirmation');
      }
      if (mounted) setState(() => _completed = true);
    } catch (_) {
      if (mounted) {
        setState(
          () => _error = 'Could not complete setup. Check the code, username and connection, or ask your Supervisor for a new code.',
        );
      }
    } finally {
      if (mounted) {
        _clearSecrets();
        setState(() => _busy = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_busy,
    child: Scaffold(
      appBar: AppBar(title: const Text('Set up or recover account')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Form(
            key: _form,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  'Your Supervisor gives you an expiring one-time code. Choose your own password here. Internet is required.',
                ),
                const SizedBox(height: 20),
                if (_completed) ...[
                  const Text(
                    'Password set. Sign in with your username or existing email and the password you chose.',
                  ),
                  FilledButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Return to sign in'),
                  ),
                ] else ...[
                  TextFormField(
                    controller: _identifier,
                    enabled: !_busy,
                    autocorrect: false,
                    decoration: const InputDecoration(
                      labelText: 'Username or existing email',
                    ),
                    validator: (v) => (v ?? '').trim().isEmpty
                        ? 'Enter the account identifier.'
                        : null,
                  ),
                  const SizedBox(height: 16),
                  SecretTextFormField(
                    controller: _code,
                    enabled: !_busy,
                    visibilityLabel: 'code',
                    decoration: const InputDecoration(
                      labelText: 'One-time setup or recovery code',
                    ),
                    validator: (v) =>
                        RegExp(r'^[a-zA-Z0-9_-]{43}$')
                            .hasMatch((v ?? '').trim())
                        ? null
                        : 'Enter the complete one-time code.',
                  ),
                  const SizedBox(height: 16),
                  SecretTextFormField(
                    controller: _password,
                    enabled: !_busy,
                    autofillHints: const [AutofillHints.newPassword],
                    decoration: const InputDecoration(
                      labelText: 'Your new password',
                    ),
                    validator: (v) => (v ?? '').length < 12
                        ? 'Use at least 12 characters.'
                        : null,
                  ),
                  const SizedBox(height: 16),
                  SecretTextFormField(
                    controller: _confirm,
                    enabled: !_busy,
                    autofillHints: const [AutofillHints.newPassword],
                    decoration: const InputDecoration(
                      labelText: 'Confirm new password',
                    ),
                    validator: (v) =>
                        v != _password.text ? 'Passwords must match.' : null,
                  ),
                  const SizedBox(height: 20),
                  if (_error != null)
                    Semantics(liveRegion: true, child: Text(_error!)),
                  FilledButton(
                    onPressed: _busy ? null : _submit,
                    child: Text(
                      _busy ? 'Setting password…' : 'Set my password',
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    ),
  );
}
