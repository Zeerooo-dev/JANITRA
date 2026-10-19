import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'function_message.dart';
import 'supervisor_pin_setup_sheet.dart';
import '../../core/access_notice.dart';

class PinManagementPage extends StatefulWidget {
  const PinManagementPage({
    super.key,
    required this.client,
    required this.kind,
    required this.userId,
    required this.fullName,
    required this.agencyId,
    required this.siteId,
  });
  final SupabaseClient client;
  final String kind, userId, fullName, agencyId;
  final String? siteId;
  @override
  State<PinManagementPage> createState() => _PinManagementPageState();
}

class _PinManagementPageState extends State<PinManagementPage> {
  bool _loading = true, _configured = false, _canReset = false;
  String? _changedAt, _error;
  String get _title =>
      widget.kind == 'employee' ? 'Employee PIN' : 'Supervisor PIN';
  Map<String, dynamic> get _scope => {
    'kind': widget.kind,
    'user_id': widget.userId,
    'agency_id': widget.agencyId,
    'site_id': widget.siteId,
  };

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
      _canReset = false;
    });
    try {
      final response = await invokeProtected(
        widget.client,
        'manage-pins',
        body: {'action': 'status', ..._scope},
      );
      final data = response.data;
      if (data is! Map ||
          data['configured'] is! bool ||
          data['can_reset'] is! bool) {
        throw const FormatException('Invalid PIN status');
      }
      String? changedAt;
      if (data['changed_at'] != null) {
        changedAt = DateTime.parse(data['changed_at'] as String)
            .toLocal()
            .toString()
            .substring(0, 16);
      }
      if (mounted) {
        setState(() {
          _configured = data['configured'] as bool;
          _canReset = data['can_reset'] as bool;
          _changedAt = changedAt;
        });
      }
    } catch (error) {
      if (mounted) setState(() => _error = functionMessage(error));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _setPin() async {
    final saved = await showModalBottomSheet<bool>(
      context: context,
      enableDrag: false,
      isScrollControlled: true,
      useSafeArea: true,
      constraints: const BoxConstraints(maxWidth: 620),
      builder: (_) => PinSetupSheet(
        client: widget.client,
        scope: _scope,
        resetting: _configured,
        isEmployee: widget.kind == 'employee',
        employeeName: widget.fullName,
      ),
    );
    if (saved == true && mounted) await _load();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final isSupervisor = widget.kind == 'supervisor';
    return Scaffold(
      appBar: AppBar(title: Text(_title)),
      body: SafeArea(
        child: _loading
            ? const Center(
                child: CircularProgressIndicator(
                  semanticsLabel: 'Loading PIN status',
                ),
              )
            : SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 520),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          widget.fullName,
                          style: theme.textTheme.titleLarge,
                        ),
                        const SizedBox(height: 18),
                        if (_error != null) ...[
                          Semantics(
                            liveRegion: true,
                            child: Text(
                              _error!,
                              style: TextStyle(color: colors.error),
                            ),
                          ),
                          TextButton(
                            onPressed: _load,
                            child: const Text('Retry'),
                          ),
                        ] else ...[
                          Card(
                            child: Padding(
                              padding: const EdgeInsets.all(18),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  Row(
                                    children: [
                                      Icon(
                                        _configured
                                            ? Icons.verified_user_outlined
                                            : Icons.shield_outlined,
                                        color: colors.primary,
                                        size: 28,
                                      ),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              _configured
                                                  ? 'PIN configured'
                                                  : 'No PIN configured',
                                              style:
                                                  theme.textTheme.titleMedium,
                                            ),
                                            if (_changedAt != null)
                                              Text(
                                                'Last updated: $_changedAt',
                                                style:
                                                    theme.textTheme.bodySmall,
                                              ),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 14),
                                  Text(
                                    isSupervisor
                                        ? 'Used to confirm work. Final approval is separate.'
                                        : 'Existing PINs cannot be viewed. Share the new PIN privately with the employee.',
                                    style: theme.textTheme.bodyMedium,
                                  ),
                                  const SizedBox(height: 18),
                                  if (_canReset)
                                    FilledButton.icon(
                                      onPressed: _setPin,
                                      icon: Icon(
                                        _configured
                                            ? Icons.lock_reset_outlined
                                            : Icons.add_moderator_outlined,
                                      ),
                                      label: Text(
                                        _configured ? 'Reset PIN' : 'Set PIN',
                                      ),
                                    )
                                  else
                                    Text(
                                      'This account has assignments outside your scope. A Supervisor authorized for all assignments must manage its PIN.',
                                      style: theme.textTheme.bodySmall
                                          ?.copyWith(color: colors.error),
                                    ),
                                ],
                              ),
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
}
