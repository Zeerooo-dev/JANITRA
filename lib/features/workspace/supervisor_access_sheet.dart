import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/access_notice.dart';
import '../../core/secret_text_form_field.dart';
import 'function_message.dart';

class SupervisorAccessSheet extends StatefulWidget {
  const SupervisorAccessSheet({
    super.key,
    required this.client,
    required this.user,
    required this.assignments,
    required this.agencies,
    required this.sites,
  });
  final SupabaseClient client;
  final Map<String, dynamic> user;
  final List<Map<String, dynamic>> assignments, agencies, sites;
  @override
  State<SupervisorAccessSheet> createState() => _SupervisorAccessSheetState();
}

class _SupervisorAccessSheetState extends State<SupervisorAccessSheet>
    with WidgetsBindingObserver {
  final _form = GlobalKey<FormState>();
  final _password = TextEditingController();
  late final _name = TextEditingController(
    text: widget.user['full_name'] as String,
  );
  late String _agency = widget.user['agency_id'] as String;
  late bool _active =
      (widget.user['account_active'] ?? widget.user['is_active']) == true;
  late bool _agencyWide = widget.assignments.any(
    (r) =>
        r['agency_id'] == _agency &&
        r['site_id'] == null &&
        r['is_active'] == true,
  );
  late final Set<String> _selected = widget.assignments
      .where((r) => r['is_active'] == true && r['site_id'] is String)
      .map((r) => r['site_id'] as String)
      .toSet();
  bool _busy = false;
  String? _error;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _password.dispose();
    _name.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) _password.clear();
  }

  Future<void> _save() async {
    if (_busy || !_form.currentState!.validate()) return;
    if (!_agencyWide && _selected.isEmpty) {
      setState(() => _error = 'Select at least one workplace.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final result = await invokeProtected(
        widget.client,
        'manage-users',
        body: {
          'action': 'manage_supervisor',
          'agency_id': _agency,
          'user_id': widget.user['user_id'],
          'full_name': _name.text.trim(),
          'is_active': _active,
          'site_ids': _agencyWide ? null : _selected.toList(),
          'password': _password.text,
        },
      );
      if (result.data is! Map || result.data['updated'] != true) {
        throw const FormatException('No access confirmation received.');
      }
      if (mounted) Navigator.pop(context, true);
    } catch (error) {
      if (mounted) setState(() => _error = functionMessage(error));
    } finally {
      _password.clear();
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_busy,
    child: Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * .87,
        ),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(22),
          child: Form(
            key: _form,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Edit Supervisor access',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 12),
                const Text(
                  'Saving replaces this Supervisor’s current agency and site permissions and requires them to sign in again.',
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _name,
                  enabled: !_busy,
                  maxLength: 200,
                  decoration: const InputDecoration(labelText: 'Full name'),
                  validator: (v) =>
                      (v ?? '').trim().isEmpty ? 'Enter a name.' : null,
                ),
                DropdownButtonFormField<String>(
                  initialValue: _agency,
                  isExpanded: true,
                  itemHeight: null,
                  decoration: const InputDecoration(
                    labelText: 'Manpower company',
                  ),
                  items: widget.agencies
                      .map(
                        (a) => DropdownMenuItem(
                          value: a['id'] as String,
                          child: Text(
                            a['name'] as String,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      )
                      .toList(),
                  onChanged: _busy
                      ? null
                      : (v) => setState(() {
                          _agency = v!;
                          _selected.clear();
                        }),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<bool>(
                  initialValue: _agencyWide,
                  isExpanded: true,
                  itemHeight: null,
                  decoration: const InputDecoration(
                    labelText: 'Supervisor access',
                  ),
                  items: const [
                    DropdownMenuItem(value: true, child: Text('Company-Wide')),
                    DropdownMenuItem(
                      value: false,
                      child: Text('Site-Specific'),
                    ),
                  ],
                  onChanged: _busy
                      ? null
                      : (v) => setState(() => _agencyWide = v!),
                ),
                const Text(
                  'Company-Wide covers all manpower companies. Site-Specific covers selected workplaces.',
                ),
                if (!_agencyWide)
                  for (final s in widget.sites.where(
                    (s) => s['agency_id'] == _agency,
                  ))
                    CheckboxListTile(
                      title: Text(s['name'] as String),
                      value: _selected.contains(s['id']),
                      onChanged: _busy
                          ? null
                          : (v) => setState(() {
                              if (v == true) {
                                _selected.add(s['id'] as String);
                              } else {
                                _selected.remove(s['id']);
                              }
                            }),
                    ),
                SwitchListTile(
                  title: const Text('Account active'),
                  value: _active,
                  onChanged: _busy ? null : (v) => setState(() => _active = v),
                ),
                const Text('Confirm your account password'),
                const SizedBox(height: 8),
                Semantics(
                  label: 'Confirm your account password',
                  child: SecretTextFormField(
                    controller: _password,
                    enabled: !_busy,
                    autofillHints: const [AutofillHints.password],
                    validator: (v) =>
                        (v ?? '').isEmpty ? 'Enter your password.' : null,
                  ),
                ),
                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: Semantics(liveRegion: true, child: Text(_error!)),
                  ),
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: _busy ? null : _save,
                  child: Text(_busy ? 'Saving…' : 'Save access'),
                ),
                TextButton(
                  onPressed: _busy ? null : () => Navigator.pop(context, false),
                  child: const Text('Cancel'),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}
