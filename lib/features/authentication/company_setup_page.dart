import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/app_theme.dart';

class CompanySetupPage extends StatefulWidget {
  const CompanySetupPage({
    super.key,
    required this.client,
    required this.onSaved,
  });
  final SupabaseClient client;
  final VoidCallback onSaved;

  @override
  State<CompanySetupPage> createState() => _CompanySetupPageState();
}

class _CompanySetupPageState extends State<CompanySetupPage> {
  final _form = GlobalKey<FormState>();
  final _company = TextEditingController();
  final _name = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _company.dispose();
    _name.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_busy || !_form.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final result = await widget.client.rpc(
        'setup_manpower_company',
        params: {
          'company_name': _company.text.trim(),
          'supervisor_name': _name.text.trim(),
        },
      );
      if (result is! String || result.isEmpty) {
        throw const FormatException('Missing agency identifier');
      }
      if (mounted) widget.onSaved();
    } catch (_) {
      if (mounted) {
        setState(
          () => _error = 'Could not register your company. Check your connection and try again.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String? _requiredName(String? value) =>
      value == null || value.trim().isEmpty ? 'Enter a name.' : null;

  Future<void> _signOut() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.client.auth.signOut();
    } catch (_) {
      if (mounted) {
        setState(
          () => _error =
              'Could not sign out. Check your connection and try again.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Row(
          children: [
            JanitraLogo(size: 32),
            SizedBox(width: 10),
            Text('JANITRA'),
          ],
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
                  'Register your manpower company',
                  style: TextStyle(fontSize: 24, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 16),
                const Text(
                  'Enter the name of your manpower agency or third-party service provider. Client companies and workplaces can be added later.',
                  style: TextStyle(fontSize: 16),
                ),
                const SizedBox(height: 24),
                TextFormField(
                  controller: _company,
                  enabled: !_busy,
                  maxLength: 200,
                  textCapitalization: TextCapitalization.words,
                  textInputAction: TextInputAction.next,
                  decoration: const InputDecoration(
                    labelText: 'Manpower company name',
                  ),
                  validator: _requiredName,
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _name,
                  enabled: !_busy,
                  maxLength: 200,
                  textCapitalization: TextCapitalization.words,
                  autofillHints: const [AutofillHints.name],
                  textInputAction: TextInputAction.done,
                  onFieldSubmitted: (_) => _save(),
                  decoration: const InputDecoration(
                    labelText: 'Your full name',
                  ),
                  validator: _requiredName,
                ),
                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    child: Semantics(liveRegion: true, child: Text(_error!)),
                  ),
                const SizedBox(height: 24),
                FilledButton(
                  onPressed: _busy ? null : _save,
                  child: Text(_busy ? 'Registering…' : 'Register Company'),
                ),
                const SizedBox(height: 16),
                TextButton(
                  onPressed: _busy ? null : _signOut,
                  child: const Text('Sign Out'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
