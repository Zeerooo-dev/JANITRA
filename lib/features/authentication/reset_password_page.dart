import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/secret_text_form_field.dart';

class ResetPasswordPage extends StatefulWidget {
  const ResetPasswordPage({
    super.key,
    required this.client,
    this.initialSetup = false,
    this.onSaved,
  });
  final SupabaseClient client;
  final bool initialSetup;
  final VoidCallback? onSaved;

  @override
  State<ResetPasswordPage> createState() => _ResetPasswordPageState();
}

class _ResetPasswordPageState extends State<ResetPasswordPage> {
  final _form = GlobalKey<FormState>();
  final _password = TextEditingController();
  final _confirmation = TextEditingController();
  bool _busy = false;
  String? _message;

  @override
  void dispose() {
    _password.dispose();
    _confirmation.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_busy || !_form.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      await widget.client.auth.updateUser(
        UserAttributes(password: _password.text),
      );
      if (widget.onSaved != null) {
        if (mounted) widget.onSaved!();
      } else {
        await widget.client.auth.signOut();
      }
    } catch (_) {
      if (mounted) {
        setState(
          () => _message = 'Could not finish changing your password. Please try again or contact your supervisor.',
        );
      }
    } finally {
      if (mounted) {
        _password.clear();
        _confirmation.clear();
        setState(() => _busy = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.initialSetup ? 'Set Your Password' : 'Reset Password',
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Form(
            key: _form,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  'New Password',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 8),
                SecretTextFormField(
                  controller: _password,
                  enabled: !_busy,
                  autofillHints: const [AutofillHints.newPassword],
                  decoration: const InputDecoration(
                    labelText: 'New password',
                    helperText: 'Use at least 12 characters.',
                    helperMaxLines: 2,
                  ),
                  validator: (value) => (value?.length ?? 0) < 12
                      ? 'Use at least 12 characters.'
                      : null,
                ),
                const SizedBox(height: 16),
                SecretTextFormField(
                  controller: _confirmation,
                  enabled: !_busy,
                  autofillHints: const [AutofillHints.newPassword],
                  decoration: const InputDecoration(
                    labelText: 'Confirm password',
                  ),
                  validator: (value) => value != _password.text
                      ? 'Passwords do not match.'
                      : null,
                ),
                if (_message != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 16),
                    child: Semantics(liveRegion: true, child: Text(_message!)),
                  ),
                const SizedBox(height: 24),
                FilledButton(
                  onPressed: _busy ? null : _save,
                  child: Text(_busy ? 'Please wait…' : 'Save Password'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
