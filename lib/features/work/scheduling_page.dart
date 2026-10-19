import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import '../../core/access_notice.dart';
import '../../core/app_theme.dart';

import '../workspace/function_message.dart';
import '../workspace/workspace_access.dart';
import 'task_record.dart';
import 'work_repository.dart';
import 'work_form.dart';
import 'checklist.dart';

class SchedulingPage extends StatefulWidget {
  const SchedulingPage({
    super.key,
    required this.client,
    required this.access,
    required this.agencyId,
    required this.sites,
  });
  final SupabaseClient client;
  final WorkspaceAccess access;
  final String agencyId;
  final List<Map<String, dynamic>> sites;
  @override
  State<SchedulingPage> createState() => _SchedulingPageState();
}

class _SchedulingPageState extends State<SchedulingPage> {
  late final repo = WorkRepository(widget.client);
  List<Map<String, dynamic>> _activities = [],
      _agencies = [],
      _shifts = [],
      _rules = [],
      _people = [],
      _segments = [],
      _exceptions = [],
      _policies = [];
  bool _loading = true;
  String? _error;
  late String _agencyId = widget.agencyId;
  late List<Map<String, dynamic>> _workplaces = widget.sites;
  int _loadVersion = 0;
  String get _agencyName =>
      _agencies.where((a) => a['id'] == _agencyId).firstOrNull?['name']
          as String? ??
      'this company';
  List<Map<String, dynamic>> get _sites =>
      _workplaces.where(widget.access.managesSite).toList();
  String get today => dateOnly(manilaNow());
  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load([String? agencyId]) async {
    final version = ++_loadVersion;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final agencies =
          (await repo.rows('agencies'))
              .where(
                (a) =>
                    !widget.access.isSupervisor ||
                    widget.access.supervisesAgency(a['id'] as String),
              )
              .toList()
            ..sort(
              (a, b) => (a['name'] as String).compareTo(b['name'] as String),
            );
      if (agencies.isEmpty) {
        throw const FormatException(
          'No authorized manpower company is available. Refresh workplace access.',
        );
      }
      final wanted = agencyId ?? _agencyId;
      final selected = agencies.any((a) => a['id'] == wanted)
          ? wanted
          : agencies.first['id'] as String;
      final loaded = await Future.wait(
        [
          'work_activities',
          'shift_templates',
          'task_schedule_rules',
          'shift_segments',
          'schedule_exceptions',
          'deadline_policies',
          'sites',
        ].map((table) => repo.rows(table, agencyId: selected)),
      );
      if (!mounted || version != _loadVersion) return;
      final people = await invokeProtected(
        widget.client,
        'manage-users',
        body: {'action': 'list', 'agency_id': selected},
      );
      if (mounted && version == _loadVersion) {
        setState(() {
          _agencies = agencies;
          _agencyId = selected;
          _workplaces = loaded[6];
          _activities = loaded[0];
          _shifts = loaded[1];
          _rules = loaded[2];
          _segments = loaded[3];
          _exceptions = loaded[4];
          _policies = loaded[5];
          _people = (people.data['users'] as List)
              .cast<Map<String, dynamic>>()
              .where(
                (p) =>
                    p['role'] == 'personnel' &&
                    p['is_active'] == true &&
                    p['agency_id'] == selected &&
                    _sites.any((s) => s['id'] == p['site_id']),
              )
              .toList();
          _error = null;
        });
      }
    } catch (error) {
      if (mounted && version == _loadVersion) {
        setState(
          () => _error = error is FormatException
              ? error.message
              : functionMessage(error),
        );
      }
    } finally {
      if (mounted && version == _loadVersion) setState(() => _loading = false);
    }
  }

  String siteName(Object? id) =>
      _sites.where((s) => s['id'] == id).firstOrNull?['name'] as String? ??
      'Workplace';
  Map<String, String> get _siteChoices => {
    for (final s in _sites) s['id'] as String: s['name'] as String,
  };
  Map<String, String> get _personChoices => {
    for (final p in _people)
      '${p['user_id']}|${p['site_id']}':
          '${p['full_name']} · ${siteName(p['site_id'])}',
  };
  Map<String, String> get _cleaningPersonChoices => {
    for (final entry in _personChoices.entries)
      if (_activities.any(
        (a) =>
            a['site_id'] == entry.key.split('|').last && a['is_active'] == true,
      ))
        entry.key: entry.value,
  };
  String get _missingPersonnel =>
      'No active Personnel assigned to your workplaces in $_agencyName. '
      '${_agencies.length > 1 ? 'Select another company or add Personnel' : 'Add Personnel'} in Team.';
  Future<void> _form(
    String title,
    String action,
    List<WorkField> fields, {
    List<int>? days,
    Map<String, dynamic> extra = const {},
    Map<String, dynamic> Function(Map<String, dynamic>)? prepare,
  }) async {
    final saved = await showModalBottomSheet<bool>(
      context: context,
      enableDrag: false,
      isScrollControlled: true,
      useSafeArea: true,
      constraints: const BoxConstraints(maxWidth: 620),
      builder: (_) => WorkForm(
        sheet: true,
        title: title,
        fields: fields,
        initialDays: days,
        save: (values) async {
          final data = prepare?.call(values) ?? values;
          if (data['is_active'] is String) {
            data['is_active'] = data['is_active'] == 'true';
          }
          await repo.command(action, {
            'agency_id': _agencyId,
            ...extra,
            ...data,
          });
        },
      ),
    );
    if (saved == true && mounted) await _load();
  }

  Widget _deleteButton(String kind, Map<String, dynamic> item) =>
      widget.access.managesSite({
        'id': item['site_id'],
        'agency_id': item['agency_id'],
      })
      ? IconButton(
          tooltip: 'Delete $kind',
          icon: const Icon(Icons.delete_outline),
          onPressed: () => _delete(kind, item),
        )
      : const Icon(Icons.chevron_right);

  Future<void> _delete(String kind, Map<String, dynamic> item) async {
    final action = switch (kind) {
      'activity' => 'activity_delete',
      'work shift' => 'shift_delete',
      _ => 'rule_delete',
    };
    final requestId = const Uuid().v4();
    final name = item['name'] as String? ?? 'cleaning schedule';
    final deleted = await showModalBottomSheet<bool>(
      context: context,
      enableDrag: false,
      isScrollControlled: true,
      useSafeArea: true,
      constraints: const BoxConstraints(maxWidth: 620),
      builder: (_) => WorkForm(
        sheet: true,
        title: 'Delete $name?',
        button: 'Delete',
        description: kind == 'cleaning schedule'
            ? 'Remove this cleaning schedule and cancel its future unsubmitted tasks? Submitted work and history will be kept.'
            : 'Remove this $kind, its linked cleaning schedules and their future unsubmitted tasks? Submitted work and history will be kept.',
        fields: const [],
        save: (_) async {
          final result = await repo.command(action, {
            'id': item['id'],
            'agency_id': item['agency_id'],
            'site_id': item['site_id'],
          }, requestId: requestId);
          if (result['deleted'] != true) {
            throw const FormatException('No deletion confirmation received.');
          }
        },
      ),
    );
    if (deleted == true && mounted) await _load();
  }

  Future<void> _activity([Map<String, dynamic>? old]) => _form(
    old == null ? 'Add Cleaning Activity' : 'Edit Cleaning Activity',
    'activity_save',
    [
      WorkField(
        'site_id',
        'Workplace',
        choices: _siteChoices,
        value: old?['site_id'] as String? ?? '',
      ),
      WorkField('name', 'Activity name', value: old?['name'] as String? ?? ''),
      WorkField(
        'is_active',
        'Activity enabled',
        value: (old?['is_active'] ?? true).toString(),
        choices: const {'true': 'Enabled', 'false': 'Paused'},
      ),
      WorkField(
        'location',
        'Location',
        optional: true,
        value: old?['location'] as String? ?? '',
      ),
      WorkField(
        'instructions',
        'Detailed instructions',
        optional: true,
        lines: 3,
        value: old?['instructions'] as String? ?? '',
      ),
      WorkField(
        'checklist_lines',
        'Checklist items, one per line (optional)',
        optional: true,
        lines: 5,
        value: (old?['checklist_items'] as List? ?? [])
            .map((item) => item['label'])
            .join('\n'),
      ),
    ],
    extra: {if (old != null) 'id': old['id']},
    prepare: (data) => {
      ...data,
      'checklist_items': parseChecklist(
        data.remove('checklist_lines') as String? ?? '',
        previous: old?['checklist_items'] as List? ?? [],
      ),
    }..remove('checklist_lines'),
  );
  List<Map<String, dynamic>> _parseSegments(String value, String kind) {
    return value.split('\n').where((v) => v.trim().isNotEmpty).map((line) {
      final parts = line.trim().split('-');
      if (parts.length != 2) {
        throw const FormatException(
          'Use one shift per line, such as 07:00-12:00.',
        );
      }
      final start = clockMinute(parts[0]), end = clockMinute(parts[1]);
      return <String, dynamic>{
        'start': start,
        'end': end <= start ? end + 1440 : end,
        'kind': kind,
      };
    }).toList();
  }

  String _clock(int minute) =>
      '${(minute ~/ 60 % 24).toString().padLeft(2, '0')}:${(minute % 60).toString().padLeft(2, '0')}';
  String _segmentText(Object? id, String kind) => _segments
      .where((s) => s['template_id'] == id && s['kind'] == kind)
      .map(
        (s) =>
            '${_clock(s['start_minute'] as int)}-${_clock(s['end_minute'] as int)}',
      )
      .join('\n');
  Future<void> _shift([Map<String, dynamic>? old]) => _form(
    old == null ? 'Add Work Schedule' : 'Edit Work Schedule',
    'shift_save',
    [
      WorkField(
        'person',
        'Personnel and workplace',
        choices: _personChoices,
        value: old == null ? '' : '${old['user_id']}|${old['site_id']}',
      ),
      WorkField(
        'name',
        'Schedule name',
        value: old?['name'] as String? ?? 'Work schedule',
      ),
      WorkField(
        'is_active',
        'Work schedule enabled',
        value: (old?['is_active'] ?? true).toString(),
        choices: const {'true': 'Enabled', 'false': 'Paused'},
      ),
      WorkField(
        'starts_on',
        'Start date',
        value: old?['starts_on'] as String? ?? today,
        validate: validDate,
        input: WorkFieldInput.date,
      ),
      WorkField(
        'ends_on',
        'End date (optional)',
        value: old?['ends_on'] as String? ?? '',
        optional: true,
        validate: validDate,
        input: WorkFieldInput.date,
      ),
      WorkField(
        'work',
        'Working hours',
        input: WorkFieldInput.timeRanges,
        lines: 3,
        value: old == null
            ? '07:00-12:00\n16:00-20:00'
            : _segmentText(old['id'], 'work'),
      ),
      WorkField(
        'breaks',
        'Breaks (optional)',
        input: WorkFieldInput.timeRanges,
        optional: true,
        lines: 2,
        value: old == null ? '' : _segmentText(old['id'], 'break'),
      ),
    ],
    days: old == null
        ? [1, 2, 3, 4, 5, 6]
        : (old['weekdays'] as List).cast<int>(),
    extra: {if (old != null) 'id': old['id']},
    prepare: (data) {
      final person = (data.remove('person') as String).split('|');
      final work = _parseSegments(data.remove('work') as String, 'work');
      final breaks = _parseSegments(
        data.remove('breaks') as String? ?? '',
        'break',
      );
      for (final b in breaks) {
        if (!work.any(
              (w) => b['start'] >= w['start'] && b['end'] <= w['end'],
            ) &&
            work.any(
              (w) =>
                  b['start'] + 1440 >= w['start'] &&
                  b['end'] + 1440 <= w['end'],
            )) {
          b['start'] += 1440;
          b['end'] += 1440;
        }
      }
      return {
        ...data,
        'user_id': person[0],
        'site_id': person[1],
        'segments': [...work, ...breaks],
      };
    },
  );
  Future<void> _rule([Map<String, dynamic>? old]) => _form(
    old == null ? 'Schedule Cleaning' : 'Edit Cleaning Schedule',
    'rule_save',
    [
      WorkField(
        'is_active',
        'Cleaning schedule enabled',
        value: (old?['is_active'] ?? true).toString(),
        choices: const {'true': 'Enabled', 'false': 'Paused'},
      ),
      WorkField(
        'person',
        'Personnel and workplace',
        choices: old == null ? _cleaningPersonChoices : _personChoices,
        value: old == null ? '' : '${old['user_id']}|${old['site_id']}',
      ),
      WorkField(
        'activity_id',
        'Cleaning activity',
        value: old?['activity_id'] as String? ?? '',
        choicesFor: (values) => {
          for (final a in _activities.where(
            (a) =>
                a['site_id'] == values['person']?.split('|').last &&
                a['is_active'] == true,
          ))
            a['id'] as String: a['name'] as String,
        },
      ),
      WorkField(
        'shift_id',
        'Work schedule (optional)',
        optional: true,
        value: old?['shift_id'] as String? ?? '',
        choicesFor: (values) => {
          for (final s in _shifts.where(
            (s) =>
                '${s['user_id']}|${s['site_id']}' == values['person'] &&
                s['is_active'] == true,
          ))
            s['id'] as String: s['name'] as String,
        },
      ),
      WorkField(
        'starts_on',
        'First date',
        value: old?['starts_on'] as String? ?? today,
        validate: validDate,
        input: WorkFieldInput.date,
      ),
      WorkField(
        'ends_on',
        'Last date (same date for one-time work)',
        optional: true,
        value: old?['ends_on'] as String? ?? '',
        validate: validDate,
        input: WorkFieldInput.date,
      ),
      WorkField(
        'time',
        'First cleaning time',
        value: old == null ? '08:00' : _clock(old['at_minute'] as int),
        validate: validTime,
        input: WorkFieldInput.time,
      ),
      WorkField(
        'until',
        'Last time for repeated activities (optional)',
        optional: true,
        value: old?['until_minute'] is int
            ? _clock(old!['until_minute'] as int)
            : '',
        validate: validTime,
        input: WorkFieldInput.time,
      ),
      WorkField(
        'interval',
        'Repeat every minutes (optional)',
        optional: true,
        value: old?['interval_minutes']?.toString() ?? '',
        validate: (v) =>
            int.tryParse(v) == null ? 'Enter a number of minutes.' : null,
      ),
    ],
    days: old == null
        ? [1, 2, 3, 4, 5, 6]
        : (old['weekdays'] as List).cast<int>(),
    extra: {if (old != null) 'id': old['id']},
    prepare: (data) {
      final person = (data.remove('person') as String).split('|');
      final at = clockMinute(data.remove('time') as String);
      final until = data.remove('until') as String?;
      var end = until == null ? at : clockMinute(until);
      if (end < at) end += 1440;
      final interval = data.remove('interval') as String?;
      return {
        ...data,
        'user_id': person[0],
        'site_id': person[1],
        'at_minute': at,
        'until_minute': end,
        'interval_minutes': interval == null ? null : int.parse(interval),
      };
    },
  );
  Future<void> _exception() => _form(
    'Holiday, Substitute or Changed Time',
    'exception_save',
    [
      WorkField(
        'rule_id',
        'Cleaning schedule',
        choices: {
          for (final r in _rules)
            r['id'] as String:
                '${_activities.where((a) => a['id'] == r['activity_id']).firstOrNull?['name'] ?? 'Cleaning'} · ${_people.where((p) => p['user_id'] == r['user_id']).firstOrNull?['full_name'] ?? 'Personnel'} · ${siteName(r['site_id'])}',
        },
      ),
      WorkField(
        'work_date',
        'Work date',
        value: today,
        validate: validDate,
        input: WorkFieldInput.date,
      ),
      const WorkField(
        'cancelled',
        'Cancel work for this date?',
        choices: {'false': 'No', 'true': 'Yes, holiday or no work'},
        value: 'false',
      ),
      WorkField(
        'substitute_id',
        'Substitute (optional)',
        optional: true,
        choices: {
          for (final p in _people)
            p['user_id'] as String:
                '${p['full_name']} · ${siteName(p['site_id'])}',
        },
      ),
      const WorkField(
        'time',
        'Changed time (optional)',
        optional: true,
        validate: validTime,
        input: WorkFieldInput.time,
      ),
      const WorkField('reason', 'Reason', lines: 2),
    ],
    prepare: (data) {
      final rule = _rules.singleWhere((r) => r['id'] == data['rule_id']);
      final time = data.remove('time') as String?;
      return {
        ...data,
        'site_id': rule['site_id'],
        'cancelled': data['cancelled'] == 'true',
        'at_minute': time == null ? null : clockMinute(time),
      };
    },
  );
  Future<void> _policy() => _form(
    'Approval Deadlines',
    'policy_save',
    [
      WorkField('site_id', 'Workplace', choices: _siteChoices),
      const WorkField(
        'weekday',
        'Workday',
        choices: {
          '1': 'Monday',
          '2': 'Tuesday',
          '3': 'Wednesday',
          '4': 'Thursday',
          '5': 'Friday',
          '7': 'Sunday',
        },
      ),
      const WorkField(
        'hours',
        'Hours after scheduled time (1-168)',
        value: '24',
      ),
    ],
    prepare: (data) => {
      ...data,
      'weekday': int.parse(data['weekday'] as String),
      'hours': int.parse(data['hours'] as String),
    },
  );
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('Schedules & activities'),
      actions: [
        IconButton(
          tooltip: 'Refresh schedules',
          onPressed: _loading ? null : _load,
          icon: const Icon(Icons.refresh),
        ),
      ],
    ),
    body: SafeArea(
      child: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(18, 8, 18, 28),
                children: [
                  if (_agencies.isNotEmpty) ...[
                    if (_agencies.length > 1)
                      DropdownButtonFormField<String>(
                        key: ValueKey('scheduling-company/$_agencyId'),
                        initialValue: _agencyId,
                        isExpanded: true,
                        itemHeight: null,
                        decoration: const InputDecoration(
                          labelText: 'Manpower company',
                        ),
                        items: [
                          for (final a in _agencies)
                            DropdownMenuItem(
                              value: a['id'] as String,
                              child: Text(a['name'] as String),
                            ),
                        ],
                        onChanged: (id) {
                          if (id != null && id != _agencyId) _load(id);
                        },
                      )
                    else
                      InputDecorator(
                        decoration: const InputDecoration(
                          labelText: 'Manpower company',
                        ),
                        child: Text(_agencyName),
                      ),
                    const SizedBox(height: 12),
                  ],
                  if (_error != null) ...[
                    Semantics(liveRegion: true, child: Text(_error!)),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: TextButton.icon(
                        onPressed: _load,
                        icon: const Icon(Icons.refresh),
                        label: const Text('Retry'),
                      ),
                    ),
                  ],
                  SectionHeading(
                    'Cleaning activities',
                    count: _activities.length,
                    action: 'Add',
                    onAction: _sites.isEmpty ? null : () => _activity(),
                  ),
                  if (_activities.isEmpty)
                    JanitraEmptyState(
                      _sites.isEmpty
                          ? 'Add a workplace in $_agencyName before creating activities.'
                          : 'Create an activity in $_agencyName to get started.',
                      icon: Icons.cleaning_services_outlined,
                    )
                  else
                    ..._activities.map(
                      (a) => Card(
                        child: ListTile(
                          leading: const Icon(Icons.cleaning_services_outlined),
                          title: Text(a['name'] as String),
                          subtitle: Text(
                            '${siteName(a['site_id'])} · ${a['location']}',
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                          trailing: _deleteButton('activity', a),
                          onTap: () => _activity(a),
                        ),
                      ),
                    ),
                  SectionHeading(
                    'Work shifts',
                    count: _shifts.length,
                    action: 'Add',
                    onAction: _people.isEmpty ? null : () => _shift(),
                  ),
                  if (_shifts.isEmpty)
                    JanitraEmptyState(
                      _people.isEmpty
                          ? _missingPersonnel
                          : 'No shifts created yet.',
                      icon: Icons.access_time_outlined,
                    )
                  else
                    ..._shifts.map(
                      (s) => Card(
                        child: ListTile(
                          leading: const Icon(Icons.access_time_outlined),
                          title: Text(s['name'] as String),
                          subtitle: Text(
                            _segmentText(s['id'], 'work'),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                          trailing: _deleteButton('work shift', s),
                          onTap: () => _shift(s),
                        ),
                      ),
                    ),
                  SectionHeading(
                    'Cleaning schedules',
                    count: _rules.length,
                    action: 'Add',
                    onAction: _cleaningPersonChoices.isEmpty
                        ? null
                        : () => _rule(),
                  ),
                  if (_rules.isEmpty)
                    JanitraEmptyState(
                      _people.isEmpty
                          ? _missingPersonnel
                          : _cleaningPersonChoices.isEmpty
                          ? 'Create an enabled activity at a Personnel workplace in $_agencyName first.'
                          : 'No cleaning schedules yet.',
                      icon: Icons.event_note_outlined,
                    )
                  else
                    ..._rules.map(
                      (r) => Card(
                        child: ListTile(
                          leading: const Icon(Icons.event_note_outlined),
                          title: Text(
                            _activities
                                        .where(
                                          (a) => a['id'] == r['activity_id'],
                                        )
                                        .firstOrNull?['name']
                                    as String? ??
                                'Cleaning',
                          ),
                          subtitle: Text(
                            '${_clock(r['at_minute'] as int)} · '
                            '${siteName(r['site_id'])}',
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                          trailing: _deleteButton('cleaning schedule', r),
                          onTap: () => _rule(r),
                        ),
                      ),
                    ),
                  if (_rules.isNotEmpty || _exceptions.isNotEmpty)
                    Card(
                      child: Column(
                        children: [
                          ListTile(
                            leading: const Icon(Icons.event_busy_outlined),
                            title: const Text('Schedule exceptions'),
                            subtitle: Text(
                              '${_exceptions.length} changes or holidays',
                            ),
                            trailing: const Icon(Icons.chevron_right),
                            enabled: _rules.isNotEmpty,
                            onTap: _rules.isEmpty ? null : _exception,
                          ),
                          if (_exceptions.isNotEmpty) ...[
                            const Divider(height: 1, indent: 54),
                            for (final e in _exceptions.take(3))
                              ListTile(
                                dense: true,
                                title: Text(
                                  '${e['work_date']} · '
                                  '${e['cancelled'] == true ? 'Cancelled' : 'Changed'}',
                                ),
                                subtitle: Text(
                                  e['reason'] as String,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            if (_exceptions.length > 3)
                              Padding(
                                padding: const EdgeInsets.all(12),
                                child: Text(
                                  '${_exceptions.length - 3} more exceptions',
                                  style: TextStyle(
                                    color: Theme.of(context)
                                        .colorScheme
                                        .onSurfaceVariant,
                                  ),
                                ),
                              ),
                          ],
                        ],
                      ),
                    ),
                  const SizedBox(height: 12),
                  Card(
                    child: ExpansionTile(
                      leading: Icon(
                        Icons.tune_outlined,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                      title: const Text('Approval deadlines'),
                      subtitle: const Text(
                        'Saturday closes Monday at noon (PHT)',
                      ),
                      childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                      expandedCrossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          'Saturday reviews close the following Monday '
                          'at 12:00 noon, Manila time. Existing deadlines stay unchanged.',
                          style: TextStyle(
                            color: Theme.of(context)
                                .colorScheme
                                .onSurfaceVariant,
                          ),
                        ),
                        for (final p in _policies)
                          ListTile(
                            dense: true,
                            contentPadding: EdgeInsets.zero,
                            title: Text(
                              '${siteName(p['site_id'])} · '
                              '${const ['', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'][p['weekday'] as int]}',
                            ),
                            subtitle: Text(
                              '${p['hours']} hours after scheduled time',
                            ),
                          ),
                        Align(
                          alignment: Alignment.centerLeft,
                          child: TextButton.icon(
                            onPressed: _sites.isEmpty ? null : _policy,
                            icon: const Icon(Icons.settings_outlined),
                            label: const Text('Configure deadlines'),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
    ),
  );
}
