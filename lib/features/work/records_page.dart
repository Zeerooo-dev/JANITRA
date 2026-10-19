import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'work_repository.dart';
import 'task_record.dart';
import '../workspace/function_message.dart';

class RecordsPage extends StatefulWidget {
  const RecordsPage({
    super.key,
    required this.client,
    required this.kind,
    this.agencyId,
  });

  final SupabaseClient client;
  final String kind;
  final String? agencyId;

  @override
  State<RecordsPage> createState() => _RecordsPageState();
}

class _RecordsPageState extends State<RecordsPage> {
  List<Map<String, dynamic>> _rows = [];
  String? _error;
  bool _loading = true;
  String _filter = 'all';

  String get table => widget.kind == 'Notifications'
      ? 'task_notifications'
      : widget.kind == 'Agency History'
      ? 'agency_transfers'
      : 'audit_events';

  bool get _isAudit => table == 'audit_events';

  List<Map<String, dynamic>> get _visibleRows => _isAudit && _filter != 'all'
      ? _rows.where((r) => r['action'] == _filter).toList()
      : _rows;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final repo = WorkRepository(widget.client);
      final rows = await repo.rows(table, agencyId: widget.agencyId);
      rows.sort(
        (a, b) =>
            b['occurred_at'].toString().compareTo(a['occurred_at'].toString()),
      );
      if (mounted) {
        setState(() {
          _rows = rows;
          _error = null;
        });
      }
      if (widget.kind == 'Notifications') {
        await repo.command('read_notifications', {});
      }
    } catch (e) {
      if (mounted) setState(() => _error = functionMessage(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _openAudit(Map<String, dynamic> record) =>
      showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        showDragHandle: true,
        builder: (_) => _AuditDetails(record: record),
      );

  @override
  Widget build(BuildContext context) {
    final rows = _visibleRows;
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.kind),
        actions: [
          IconButton(
            tooltip: 'Refresh records',
            onPressed: _loading ? null : _load,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: SafeArea(
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : _error != null
            ? _RecordsMessage(
                icon: Icons.wifi_off_outlined,
                title: 'Could not load records',
                message: _error!,
                onRetry: _load,
              )
            : _rows.isEmpty
            ? const _RecordsMessage(
                icon: Icons.history_toggle_off_outlined,
                title: 'No records yet',
                message: 'New activity will appear here.',
              )
            : Column(
                children: [
                  if (_isAudit) ...[
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          '${_rows.length} recorded ${_rows.length == 1 ? 'event' : 'events'}',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ),
                    ),
                    SizedBox(
                      height: 54,
                      child: ListView(
                        scrollDirection: Axis.horizontal,
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        children: [
                          for (final filter in const [
                            ('all', 'All'),
                            ('insert', 'Added'),
                            ('update', 'Updated'),
                            ('delete', 'Removed'),
                          ]) ...[
                            Padding(
                              padding: const EdgeInsets.only(right: 8),
                              child: ChoiceChip(
                                label: Text(filter.$2),
                                selected: _filter == filter.$1,
                                onSelected: (_) =>
                                    setState(() => _filter = filter.$1),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                  Expanded(
                    child: rows.isEmpty
                        ? const _RecordsMessage(
                            icon: Icons.filter_alt_off_outlined,
                            title: 'No matching events',
                            message: 'Try another filter.',
                          )
                        : RefreshIndicator(
                            onRefresh: _load,
                            child: ListView.builder(
                              padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                              itemCount: rows.length,
                              itemBuilder: (context, index) {
                                final row = rows[index];
                                if (!_isAudit) {
                                  return _otherRecord(row);
                                }
                                final date = _recordDate(row);
                                final previousDate = index == 0
                                    ? null
                                    : _recordDate(rows[index - 1]);
                                return Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.stretch,
                                  children: [
                                    if (date != previousDate)
                                      Padding(
                                        padding: const EdgeInsets.fromLTRB(
                                          4,
                                          12,
                                          4,
                                          12,
                                        ),
                                        child: Text(
                                          _dayLabel(context, date),
                                          style: Theme.of(context)
                                              .textTheme
                                              .titleSmall,
                                        ),
                                      ),
                                    _AuditTile(
                                      record: row,
                                      onTap: () => _openAudit(row),
                                    ),
                                  ],
                                );
                              },
                            ),
                          ),
                  ),
                ],
              ),
      ),
    );
  }

  Widget _otherRecord(Map<String, dynamic> row) => Card(
    child: ListTile(
      title: Text(
        table == 'task_notifications'
            ? row['message']?.toString() ?? 'Notification'
            : row['reason']?.toString() ?? 'Agency transfer',
      ),
      subtitle: Text(
        '${_safeTime(row['occurred_at'])}${table == 'agency_transfers' ? '\n${row['source_name'] ?? ''} → ${row['destination_name'] ?? ''} · ${row['workplace_name'] ?? ''}' : ''}',
      ),
    ),
  );
}

String _safeTime(Object? timestamp) {
  try {
    return workTime(timestamp as String);
  } catch (_) {
    return 'Time unavailable';
  }
}

String _recordDate(Map<String, dynamic> row) {
  final timestamp = _safeTime(row['occurred_at']);
  return timestamp.length >= 10 ? timestamp.substring(0, 10) : timestamp;
}

String _auditEntity(Object? value) {
  const names = <String, String>{
    'agencies': 'Manpower agency',
    'client_companies': 'Client company',
    'sites': 'Workplace',
    'profiles': 'Profile',
    'role_assignments': 'Account access',
    'personnel_assignments': 'Personnel assignment',
    'activities': 'Cleaning activity',
    'shift_templates': 'Work shift',
    'shift_segments': 'Shift hours',
    'task_schedule_rules': 'Cleaning schedule',
    'task_instances': 'Task',
    'account_security_events': 'Account security',
  };
  if (names.containsKey(value)) return names[value]!;
  final text = (value ?? 'Record').toString().replaceAll('_', ' ');
  final cleaned = text.replaceAll(RegExp(r'\s+'), ' ').trim();
  if (cleaned.isEmpty) return 'Record';
  return cleaned[0].toUpperCase() + cleaned.substring(1);
}

String _dayLabel(BuildContext context, String day) {
  final date = DateTime.tryParse(day);
  return date == null
      ? day
      : MaterialLocalizations.of(context).formatMediumDate(date);
}

String _auditVerb(Object? value) => switch (value) {
  'insert' => 'Added',
  'update' => 'Updated',
  'delete' => 'Removed',
  _ => 'Changed',
};

IconData _auditIcon(Object? action) => switch (action) {
  'insert' => Icons.add_circle_outline,
  'delete' => Icons.remove_circle_outline,
  _ => Icons.edit_outlined,
};

class _AuditTile extends StatelessWidget {
  const _AuditTile({required this.record, required this.onTap});

  final Map<String, dynamic> record;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final action = _auditVerb(record['action']);
    final entity = _auditEntity(record['entity_type']);
    final changes = _auditFieldChanges(record);
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: theme.colorScheme.primaryContainer,
                  borderRadius: BorderRadius.circular(13),
                ),
                child: Icon(
                  _auditIcon(record['action']),
                  color: theme.colorScheme.onPrimaryContainer,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('$entity $action', style: theme.textTheme.titleSmall),
                    const SizedBox(height: 4),
                    Text(
                      changes.isEmpty
                          ? 'Record activity'
                          : '${changes.length} ${changes.length == 1 ? 'field' : 'fields'} changed',
                      style: theme.textTheme.bodySmall,
                    ),
                    const SizedBox(height: 6),
                    Text(
                      '${_safeTime(record['occurred_at'])} (PH)',
                      style: theme.textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right, size: 21),
            ],
          ),
        ),
      ),
    );
  }
}

class _AuditDetails extends StatelessWidget {
  const _AuditDetails({required this.record});
  final Map<String, dynamic> record;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final changes = _auditFieldChanges(record);
    return SafeArea(
      top: false,
      child: FractionallySizedBox(
        heightFactor: 0.82,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Icon(_auditIcon(record['action'])),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Event details',
                      style: theme.textTheme.titleLarge,
                    ),
                  ),
                  IconButton(
                    tooltip: 'Close',
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                '${_auditEntity(record['entity_type'])} · ${_auditVerb(record['action'])}',
                style: theme.textTheme.titleSmall,
              ),
              const SizedBox(height: 4),
              Text(
                '${_safeTime(record['occurred_at'])} (Philippine time)',
                style: theme.textTheme.bodySmall,
              ),
              const SizedBox(height: 16),
              Expanded(
                child: changes.isEmpty
                    ? Center(
                        child: Text(
                          'This event has no displayable field changes.',
                          style: theme.textTheme.bodyMedium,
                          textAlign: TextAlign.center,
                        ),
                      )
                    : ListView.separated(
                        itemCount: changes.length,
                        separatorBuilder: (_, _) => const SizedBox(height: 10),
                        itemBuilder: (context, index) {
                          final item = changes[index];
                          return Container(
                            padding: const EdgeInsets.all(14),
                            decoration: BoxDecoration(
                              color: theme.colorScheme.surfaceContainerLow,
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(
                                color: theme.colorScheme.outlineVariant,
                              ),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                Text(
                                  item.label,
                                  style: theme.textTheme.titleSmall,
                                ),
                                const SizedBox(height: 10),
                                Text(
                                  'BEFORE',
                                  style: theme.textTheme.labelSmall,
                                ),
                                const SizedBox(height: 3),
                                Text(_displayAuditValue(item.before)),
                                const SizedBox(height: 12),
                                Text(
                                  'AFTER',
                                  style: theme.textTheme.labelSmall,
                                ),
                                const SizedBox(height: 3),
                                Text(_displayAuditValue(item.after)),
                              ],
                            ),
                          );
                        },
                      ),
              ),
              const SizedBox(height: 12),
              FilledButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Close'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RecordsMessage extends StatelessWidget {
  const _RecordsMessage({
    required this.icon,
    required this.title,
    required this.message,
    this.onRetry,
  });
  final IconData icon;
  final String title;
  final String message;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 42),
          const SizedBox(height: 12),
          Text(title, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 6),
          Text(message, textAlign: TextAlign.center),
          if (onRetry != null) ...[
            const SizedBox(height: 12),
            FilledButton.tonal(onPressed: onRetry, child: const Text('Retry')),
          ],
        ],
      ),
    ),
  );
}

// Explicit allowlist: never render IDs, credentials, tokens, or private JSON.
const _auditLabels = <String, String>{
  'name': 'Name',
  'full_name': 'Full name',
  'is_active': 'Enabled',
  'role': 'Role',
  'status': 'Work status',
  'activity_name': 'Activity',
  'location': 'Location',
  'instructions': 'Instructions',
  'remarks': 'Remarks',
  'reason': 'Reason',
  'weekdays': 'Working days',
  'starts_on': 'Starts',
  'ends_on': 'Ends',
  'scheduled_at': 'Scheduled time',
  'submitted_at': 'Official submission',
  'verified_at': 'Verified time',
  'decided_at': 'Decision time',
  'decision_reason': 'Decision reason',
  'review_deadline': 'Review deadline',
  'hours': 'Deadline hours',
  'cancelled': 'Cancelled',
};

class _AuditFieldChange {
  const _AuditFieldChange(this.label, this.before, this.after);
  final String label;
  final Object? before;
  final Object? after;
}

List<_AuditFieldChange> _auditFieldChanges(Map<String, dynamic> record) {
  final before = Map<String, dynamic>.from(record['before_data'] as Map? ?? {});
  final after = Map<String, dynamic>.from(record['after_data'] as Map? ?? {});
  return [
    for (final entry in _auditLabels.entries)
      if (before[entry.key] != after[entry.key])
        _AuditFieldChange(entry.value, before[entry.key], after[entry.key]),
  ];
}

String _displayAuditValue(Object? value) {
  if (value == null || value == '') return 'Not set';
  if (value is bool) return value ? 'Yes' : 'No';
  if (value is List) return value.map((e) => e.toString()).join(', ');
  // Nested JSON can contain private data, so it is never displayed.
  if (value is Map) return 'Updated';
  final text = value.toString();
  return text.length > 240 ? '${text.substring(0, 240)}…' : text;
}

// Retained for compatibility with export/legacy tests. Only allowlisted keys.
String auditChanges(Map<String, dynamic> record) {
  final changed = _auditFieldChanges(record);
  return changed.isEmpty
      ? 'Assignment or system record changed. Personal credentials are not included.'
      : changed
            .map(
              (entry) =>
                  '${entry.label}: ${entry.before ?? 'Empty'} to ${entry.after ?? 'Empty'}',
            )
            .join('\n\n');
}
