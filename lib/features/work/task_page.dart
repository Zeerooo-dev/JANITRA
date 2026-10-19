import 'package:flutter/material.dart';

import 'dart:async';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../workspace/workspace_access.dart';
import '../workspace/function_message.dart';
import 'task_record.dart';
import 'work_repository.dart';
import 'work_form.dart';
import '../../core/app_theme.dart';
import '../../core/access_policy.dart';
import 'offline_access.dart';

class TasksPage extends StatefulWidget {
  const TasksPage({
    super.key,
    required this.client,
    required this.access,
    this.agencyId,
    this.embedded = false,
  });
  final SupabaseClient client;
  final WorkspaceAccess access;
  final String? agencyId;
  final bool embedded;
  @override
  State<TasksPage> createState() => _TasksPageState();
}

class _TasksPageState extends State<TasksPage> {
  late final repo = WorkRepository(widget.client);
  List<TaskRecord> _tasks = [];
  bool _loading = true;
  String? _error;
  String _filter = 'Today';
  bool get _supervisor => widget.agencyId != null
      ? widget.access.supervisesAgency(widget.agencyId!)
      : widget.access.isSupervisor;
  @override
  void initState() {
    super.initState();
    _filter = _supervisor ? 'Needs Confirmation' : 'Today';
    _load();
  }

  Future<void> _load() async {
    if (!_loading) setState(() => _loading = true);
    try {
      final rows = await repo.tasks(
        agencyId: _supervisor ? widget.agencyId : null,
      );
      if (mounted) {
        setState(() {
          _tasks = _supervisor
              ? rows
              : rows.where((t) => t.userId == repo.local.owner).toList();
          _error = null;
        });
      }
    } catch (error) {
      if (mounted) setState(() => _error = functionMessage(error));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  bool _show(TaskRecord t) => switch (_filter) {
    'Today' => t.text('work_date') == dateOnly(manilaNow()),
    'Needs Confirmation' =>
      ['PENDING_APPROVAL', 'REOPENED_FOR_REVIEW'].contains(t.effectiveStatus) &&
          !t.verified,
    'Pending Approval' =>
      ['PENDING_APPROVAL', 'REOPENED_FOR_REVIEW'].contains(t.effectiveStatus) &&
          t.verified,
    'Locked' => t.effectiveStatus == 'LOCKED_NOT_REVIEWED',
    _ => true,
  };
  Future<void> _openTask(TaskRecord task) async {
    await Navigator.push(
      context,
      MaterialPageRoute<void>(
        builder: (_) =>
            TaskDetailsPage(repo: repo, task: task, access: widget.access),
      ),
    );
    if (mounted) _load();
  }

  Future<void> _chooseFilter() async {
    final selected = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      builder: (context) => SafeArea(
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Padding(
                padding: EdgeInsets.all(20),
                child: Text(
                  'Show Tasks',
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
                ),
              ),
              for (final filter
                  in _supervisor
                      ? [
                          'Today',
                          'Needs Confirmation',
                          'Pending Approval',
                          'Locked',
                          'All History',
                        ]
                      : ['Today', 'All History'])
                ListTile(
                  title: Text(filter),
                  trailing: filter == _filter ? const Icon(Icons.check) : null,
                  onTap: () => Navigator.pop(context, filter),
                ),
            ],
          ),
        ),
      ),
    );
    if (mounted && selected != null) setState(() => _filter = selected);
  }

  @override
  Widget build(BuildContext context) {
    final visible = _tasks.where(_show).toList();
    return Scaffold(
      appBar: widget.embedded
          ? null
          : AppBar(
              title: Text(_supervisor ? 'Work for Review' : 'My Tasks'),
              actions: [
                IconButton(
                  tooltip: 'Refresh tasks',
                  onPressed: _loading ? null : _load,
                  icon: const Icon(Icons.refresh),
                ),
              ],
            ),
      body: SafeArea(
        child: Column(
          children: [
            if (_loading)
              const LinearProgressIndicator(semanticsLabel: 'Loading tasks'),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: _chooseFilter,
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 16,
                        ),
                      ),
                      child: Text(_filter),
                    ),
                  ),
                  if (widget.embedded)
                    IconButton(
                      tooltip: 'Refresh tasks',
                      onPressed: _loading ? null : _load,
                      icon: const Icon(Icons.refresh),
                    ),
                ],
              ),
            ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    Semantics(liveRegion: true, child: Text(_error!)),
                    TextButton(onPressed: _load, child: const Text('Retry')),
                  ],
                ),
              ),
            if (repo.cacheUnavailable)
              const Padding(
                padding: EdgeInsets.all(16),
                child: Text(
                  'Offline storage is unavailable. Reconnect to check and submit work.',
                ),
              ),
            Expanded(
              child: visible.isEmpty
                  ? Center(
                      child: Text(
                        _loading ? 'Loading…' : 'No tasks in this view.',
                      ),
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      itemCount: visible.length,
                      itemBuilder: (context, index) {
                        final t = visible[index];
                        return Card(
                          child: InkWell(
                            borderRadius: BorderRadius.circular(14),
                            child: Padding(
                              padding: const EdgeInsets.all(20),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  if (_supervisor) ...[
                                    WorkStatusBadge(
                                      label: t.verified
                                          ? statusLabel(t.effectiveStatus)
                                          : ([
                                                  'PENDING_APPROVAL',
                                                  'REOPENED_FOR_REVIEW',
                                                ].contains(t.effectiveStatus)
                                                ? 'Waiting for Confirmation'
                                                : statusLabel(
                                                    t.effectiveStatus,
                                                  )),
                                      status: t.effectiveStatus,
                                    ),
                                    const SizedBox(height: 14),
                                    Text(
                                      t.text('personnel_name'),
                                      style: const TextStyle(
                                        fontSize: 20,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                    const SizedBox(height: 6),
                                  ],
                                  Text(
                                    t.title,
                                    style: const TextStyle(
                                      fontSize: 18,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  const SizedBox(height: 10),
                                  Text(
                                    workTime(t.text('scheduled_at')),
                                    style: TextStyle(
                                      color: Theme.of(context)
                                          .colorScheme
                                          .onSurfaceVariant,
                                      fontSize: 16,
                                    ),
                                  ),
                                  const SizedBox(height: 12),
                                  if (!_supervisor)
                                    WorkStatusBadge(
                                      label: statusLabel(t.effectiveStatus),
                                      status: t.effectiveStatus,
                                    ),
                                  if (_supervisor)
                                    FilledButton(
                                      onPressed: () => _openTask(t),
                                      child: const Text('Review Task'),
                                    ),
                                ],
                              ),
                            ),
                            onTap: () => _openTask(t),
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class TaskDetailsPage extends StatefulWidget {
  const TaskDetailsPage({
    super.key,
    required this.repo,
    required this.task,
    required this.access,
  });
  final WorkRepository repo;
  final TaskRecord task;
  final WorkspaceAccess access;
  @override
  State<TaskDetailsPage> createState() => _TaskDetailsPageState();
}

class _TaskDetailsPageState extends State<TaskDetailsPage>
    with WidgetsBindingObserver {
  late TaskRecord task = widget.task;
  final _remarks = TextEditingController();
  String? _error, _notice;
  bool _busy = false, _historyOpen = false;
  bool _dirty = false, _draftConflict = false;
  Timer? _autoSave;
  Future<void> _draftWrites = Future.value();
  final Map<String, bool> _checks = {};
  List<Map<String, dynamic>> _history = [];
  bool get mine => task.userId == widget.repo.client.auth.currentUser?.id;
  bool get canSubmit =>
      mine &&
      task.effectiveStatus == 'SCHEDULED' &&
      widget.access.roles.any(
        (r) =>
            r['role'] == 'personnel' &&
            r['agency_id'] == task.agencyId &&
            r['site_id'] == task.siteId,
      );
  bool get manager => widget.access.managesSite({
    'id': task.siteId,
    'agency_id': task.agencyId,
  });
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _remarks.text = task.text('remarks');
    _checks.addAll(
      Map<String, bool>.from(task.data['checklist_results'] as Map? ?? {}),
    );
    _remarks.addListener(_changed);
    _draft();
  }

  Future<void> _draft() async {
    final initial = _remarks.text;
    try {
      final d = await widget.repo.local.draft(task.id);
      if (mounted && d != null && _remarks.text == initial) {
        _draftConflict =
            d.task.version != task.version ||
            d.task.checklistVersion != task.checklistVersion;
        _checks.addAll(d.checklist);
        _remarks.text = d.remarks;
        setState(() {});
      }
    } catch (_) {}
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _autoSave?.cancel();
    _flushDraft();
    _remarks.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) {
      _autoSave?.cancel();
      _flushDraft();
    }
  }

  void _changed() {
    if (!canSubmit || _draftConflict) return;
    _dirty = true;
    _autoSave?.cancel();
    _autoSave = Timer(const Duration(milliseconds: 400), _flushDraft);
  }

  void _flushDraft() {
    if (!_dirty || !canSubmit || _draftConflict) return;
    _dirty = false;
    final base = task,
        remarks = _remarks.text,
        checks = Map<String, bool>.of(_checks);
    _draftWrites = _draftWrites
        .then((_) async {
          final session = widget.repo.client.auth.currentSession;
          if (session == null || session.user.id != base.userId) {
            throw const AccessUnavailable();
          }
          if (!AccessPolicy.of(widget.repo.client).verified &&
              !await mayReadOfflinePersonalWork(session)) {
            throw const AccessUnavailable();
          }
          final previous = await widget.repo.local.draft(base.id);
          if (task.version != base.version || !canSubmit) return;
          await widget.repo.saveDraft(
            base,
            remarks,
            previous: previous,
            checklist: checks,
          );
        })
        .catchError((Object _) {
          if (mounted) {
            setState(
              () => _notice = 'Could not save the draft on this device. Keep your work open and retry.',
            );
          }
        });
  }

  Future<void> _run(Future<void> Function() action) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
      _notice = null;
    });
    try {
      await action();
    } catch (error) {
      if (mounted) {
        setState(
          () => _error = error is FormatException
              ? error.message
              : functionMessage(error),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _saveDraft() => _run(() async {
    if (_draftConflict) {
      throw const FormatException(
        'Review the saved draft conflict before saving over it.',
      );
    }
    final previous = await widget.repo.local.draft(task.id);
    await widget.repo.saveDraft(
      task,
      _remarks.text,
      previous: previous,
      checklist: _checks,
    );
    if (mounted) {
      setState(
        () => _notice = 'Saved Offline. Internet and your Employee PIN are needed to submit.',
      );
    }
  });
  Future<void> _submit() async {
    if (_draftConflict) {
      setState(
        () => _error = 'Resolve this draft conflict in Saved Offline Work before submitting.',
      );
      return;
    }
    if (task.checklist.any((item) => _checks[item['id']] != true)) {
      setState(
        () => _error =
            'Complete every checklist item before marking work as done.',
      );
      return;
    }
    _autoSave?.cancel();
    _flushDraft();
    await _draftWrites;
    WorkDraft? draft;
    await _run(() async {
      draft = await widget.repo.saveDraft(
        task,
        _remarks.text,
        previous: await widget.repo.local.draft(task.id),
        checklist: _checks,
      );
    });
    if (!mounted || draft == null) return;
    final accepted = await Navigator.push<TaskRecord>(
      context,
      MaterialPageRoute(
        builder: (_) => EmployeePinPage(repo: widget.repo, draft: draft!),
      ),
    );
    if (accepted != null && mounted) {
      setState(() {
        task = accepted;
        _notice =
            'Pending Approval. Your work is waiting for Supervisor review.';
      });
    }
    if (mounted) await _refreshTask();
  }

  Future<void> _refreshTask() async {
    try {
      final latest = await widget.repo.task(task.id);
      if (mounted) setState(() => task = latest);
    } catch (_) {}
  }

  Future<void> _verify() async {
    final confirmed = await showModalBottomSheet<TaskRecord>(
      context: context,
      isScrollControlled: true,
      isDismissible: false,
      enableDrag: false,
      useSafeArea: true,
      builder: (_) => SupervisorConfirmPinSheet(
        client: widget.repo.client,
        taskName: task.title,
        onConfirm: (pin) async {
          final result = await widget.repo.command('verify', {
            'task_id': task.id,
            'version': task.version,
            'pin': pin,
          });
          return TaskRecord(Map<String, dynamic>.from(result['task'] as Map));
        },
      ),
    );
    if (confirmed != null && mounted) setState(() => task = confirmed);
    if (mounted) await _refreshTask();
  }

  Future<void> _decision(String action) async {
    await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => WorkForm(
        title: action == 'approve' ? 'Final Work Approval' : 'Reject Work',
        button: action == 'approve' ? 'Approve Work' : 'Reject Work',
        fields: [
          if (action == 'reject')
            const WorkField('reason', 'Reason for rejection', lines: 3),
        ],
        save: (data) async {
          final result = await widget.repo.command(action, {
            'task_id': task.id,
            'version': task.version,
            'reason': data['reason'],
          });
          if (mounted) {
            setState(
              () => task = TaskRecord(
                Map<String, dynamic>.from(result['task'] as Map),
              ),
            );
          }
        },
      ),
    );
    if (mounted) await _refreshTask();
  }

  Future<void> _override() async {
    final tomorrow = manilaNow().add(const Duration(days: 1));
    await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => WorkForm(
        title: 'Reopen Locked Work',
        button: 'Reopen for Review',
        fields: [
          const WorkField(
            'reason',
            'Why this work needs reopening',
            lines: 3,
            validate: overrideReason,
          ),
          WorkField(
            'date',
            'New deadline date',
            value: dateOnly(tomorrow),
            input: WorkFieldInput.date,
            validate: validDate,
          ),
          const WorkField(
            'time',
            'New deadline time (Manila)',
            value: '12:00',
            input: WorkFieldInput.time,
            validate: validTime,
          ),
          const WorkField('password', 'Your account password', secret: true),
        ],
        save: (data) async {
          final d = DateTime.parse(data['date'] as String);
          final m = clockMinute(data['time'] as String);
          final deadline = DateTime.utc(
            d.year,
            d.month,
            d.day,
          ).add(Duration(minutes: m - 480));
          final result = await widget.repo.command('override', {
            'task_id': task.id,
            'version': task.version,
            'reason': data['reason'],
            'deadline': deadline.toIso8601String(),
            'password': data['password'],
          });
          if (mounted) {
            setState(
              () => task = TaskRecord(
                Map<String, dynamic>.from(result['task'] as Map),
              ),
            );
          }
        },
      ),
    );
    if (mounted) await _refreshTask();
  }

  Future<void> _historyToggle() => _run(() async {
    if (!_historyOpen) {
      _history = await widget.repo.client
          .from('task_events')
          .select()
          .eq('task_id', task.id)
          .order('occurred_at');
    }
    if (mounted) setState(() => _historyOpen = !_historyOpen);
  });
  @override
  Widget build(BuildContext context) {
    final pending = [
      'PENDING_APPROVAL',
      'REOPENED_FOR_REVIEW',
    ].contains(task.effectiveStatus);
    final person = task.text('personnel_name').trim();
    final location = [
      task.text('site_name').trim(),
      task.text('location').trim(),
    ].where((value) => value.isNotEmpty).join(' · ');
    final hasReview =
        task.submittedAtText.isNotEmpty ||
        task.verified ||
        task.text('decided_at').isNotEmpty ||
        (manager && pending);
    final checklistCount = task.checklist
        .where((item) => _checks[item['id']] == true)
        .length;
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Task Details'),
        actions: [
          IconButton(
            tooltip: 'Refresh task',
            onPressed: _busy
                ? null
                : () => _run(() async {
                    final updated = await widget.repo.task(task.id);
                    if (mounted) setState(() => task = updated);
                  }),
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 680),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(18),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          WorkStatusBadge(
                            label: statusLabel(task.effectiveStatus),
                            status: task.effectiveStatus,
                          ),
                          const SizedBox(height: 12),
                          Text(
                            task.title,
                            style: theme.textTheme.headlineSmall,
                          ),
                          if (manager && person.isNotEmpty) ...[
                            const SizedBox(height: 6),
                            Text(person, style: theme.textTheme.titleMedium),
                          ],
                          const SizedBox(height: 15),
                          _TaskDetailLine(
                            icon: Icons.schedule_outlined,
                            label: 'Scheduled',
                            value: _manilaDisplay(task.text('scheduled_at')),
                          ),
                          if (location.isNotEmpty) ...[
                            const SizedBox(height: 10),
                            _TaskDetailLine(
                              icon: Icons.place_outlined,
                              label: 'Workplace',
                              value: location,
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                  if (task.text('instructions').isNotEmpty)
                    Card(
                      child: ExpansionTile(
                        leading: const Icon(Icons.notes_outlined),
                        title: const Text('Work instructions'),
                        children: [
                          Padding(
                            padding: const EdgeInsets.fromLTRB(18, 0, 18, 18),
                            child: Align(
                              alignment: Alignment.centerLeft,
                              child: Text(task.text('instructions')),
                            ),
                          ),
                        ],
                      ),
                    ),
                  if (canSubmit) ...[
                    if (_draftConflict)
                      _TaskFeedback(
                        message: 'This draft needs review. Open Saved Offline Work to resolve the conflict.',
                        isError: true,
                      ),
                    if (task.checklist.isNotEmpty)
                      Card(
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Text(
                                'Checklist · $checklistCount/${task.checklist.length}',
                                style: theme.textTheme.titleMedium,
                              ),
                              const SizedBox(height: 8),
                              for (final item in task.checklist)
                                CheckboxListTile(
                                  contentPadding: EdgeInsets.zero,
                                  title: Text(item['label'] as String),
                                  value: _checks[item['id']] ?? false,
                                  controlAffinity:
                                      ListTileControlAffinity.leading,
                                  onChanged: _busy || _draftConflict
                                      ? null
                                      : (value) {
                                          setState(
                                            () =>
                                                _checks[item['id'] as String] =
                                                    value ?? false,
                                          );
                                          _changed();
                                        },
                                ),
                            ],
                          ),
                        ),
                      ),
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Text(
                              'Your work',
                              style: theme.textTheme.titleMedium,
                            ),
                            const SizedBox(height: 12),
                            TextField(
                              controller: _remarks,
                              enabled: !_busy,
                              maxLength: 2000,
                              maxLines: 3,
                              decoration: const InputDecoration(
                                labelText: 'Remarks (optional)',
                              ),
                            ),
                            FilledButton(
                              onPressed: _busy ? null : _submit,
                              child: const Text('Mark as Done'),
                            ),
                            TextButton(
                              onPressed: _busy ? null : _saveDraft,
                              child: const Text('Save Offline Draft'),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ] else if (task.text('remarks').isNotEmpty)
                    _TaskPanel(
                      title: 'Work remarks',
                      child: Text(task.text('remarks')),
                    ),
                  if (!canSubmit && task.checklist.isNotEmpty)
                    _TaskPanel(
                      title: 'Submitted checklist',
                      child: Column(
                        children: [
                          for (final item in task.checklist)
                            ListTile(
                              contentPadding: EdgeInsets.zero,
                              dense: true,
                              leading: Icon(
                                _checks[item['id']] == true
                                    ? Icons.check_circle_outline
                                    : Icons.radio_button_unchecked,
                                color: _checks[item['id']] == true
                                    ? readableColor(
                                        const Color(0xFF216E4B),
                                        Theme.of(context).colorScheme.surface,
                                        4.5,
                                      )
                                    : Theme.of(context)
                                          .colorScheme
                                          .onSurfaceVariant,
                              ),
                              title: Text(item['label'] as String),
                            ),
                        ],
                      ),
                    ),
                  if (hasReview)
                    _TaskPanel(
                      title: 'Submission & review',
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          if (task.submittedAtText.isNotEmpty)
                            _TaskDetailLine(
                              icon: Icons.task_alt_outlined,
                              label: 'Official submission',
                              value: _manilaDisplay(task.text('submitted_at')),
                            ),
                          if (task.verified) ...[
                            const SizedBox(height: 14),
                            _TaskDetailLine(
                              icon: Icons.verified_outlined,
                              label:
                                  'Confirmed by ${task.text('verifier_name')}',
                              value: _manilaDisplay(task.text('verified_at')),
                            ),
                          ],
                          if (task.text('decided_at').isNotEmpty) ...[
                            const SizedBox(height: 14),
                            _TaskDetailLine(
                              icon: Icons.fact_check_outlined,
                              label: 'Decision by ${task.text('decider_name')}',
                              value: _manilaDisplay(task.text('decided_at')),
                            ),
                            if (task.text('decision_reason').isNotEmpty) ...[
                              const SizedBox(height: 10),
                              Text('Reason: ${task.text('decision_reason')}'),
                            ],
                          ],
                          if (manager && pending) ...[
                            if (task.submittedAtText.isNotEmpty ||
                                task.verified)
                              const Divider(height: 28),
                            _TaskDetailLine(
                              icon: Icons.event_outlined,
                              label: 'Review deadline',
                              value: _manilaDisplay(
                                task.text('review_deadline'),
                              ),
                            ),
                            const SizedBox(height: 16),
                            if (!task.verified)
                              FilledButton.icon(
                                onPressed: _busy ? null : _verify,
                                icon: const Icon(Icons.pin_outlined),
                                label: const Text('Confirm Work'),
                              )
                            else ...[
                              FilledButton.icon(
                                onPressed: _busy
                                    ? null
                                    : () => _decision('approve'),
                                icon: const Icon(Icons.check_circle_outline),
                                label: const Text('Final Work Approval'),
                              ),
                              const SizedBox(height: 6),
                              OutlinedButton(
                                onPressed: _busy
                                    ? null
                                    : () => _decision('reject'),
                                child: const Text('Reject Work'),
                              ),
                            ],
                          ],
                        ],
                      ),
                    ),
                  if (manager && task.effectiveStatus == 'LOCKED_NOT_REVIEWED')
                    _TaskPanel(
                      title: 'Locked work',
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          _TaskDetailLine(
                            icon: Icons.lock_clock_outlined,
                            label: 'Original deadline',
                            value: _manilaDisplay(
                              task.text('original_deadline'),
                            ),
                          ),
                          const SizedBox(height: 14),
                          FilledButton(
                            onPressed: _busy ? null : _override,
                            child: const Text('Reopen Locked Work'),
                          ),
                        ],
                      ),
                    ),
                  if (_notice != null) _TaskFeedback(message: _notice!),
                  if (_error != null)
                    _TaskFeedback(message: _error!, isError: true),
                  const SizedBox(height: 4),
                  TextButton.icon(
                    onPressed: _busy ? null : _historyToggle,
                    icon: Icon(
                      _historyOpen ? Icons.expand_less : Icons.history,
                    ),
                    label: Text(
                      _historyOpen ? 'Hide Work History' : 'View Work History',
                    ),
                  ),
                  if (_historyOpen)
                    _TaskPanel(
                      title: 'Work history',
                      child: Column(
                        children: [
                          for (final event in _history)
                            ListTile(
                              contentPadding: EdgeInsets.zero,
                              title: Text(
                                event['event'].toString().replaceAll('_', ' '),
                              ),
                              subtitle: Text(
                                '${_manilaDisplay(event['occurred_at']?.toString() ?? '')}'
                                '${(event['details'] as Map?)?['reason'] == null ? '' : '\n${(event['details'] as Map)['reason']}'}',
                              ),
                            ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Compact, readable Philippines-local timestamps. The server stays authoritative.
String _manilaDisplay(String utcValue) {
  if (utcValue.isEmpty) return 'Not available';
  final parsed = DateTime.tryParse(utcValue);
  if (parsed == null) return 'Not available';
  final time = parsed.toUtc().add(const Duration(hours: 8));
  const months = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];
  final hour = time.hour % 12 == 0 ? 12 : time.hour % 12;
  final minute = time.minute.toString().padLeft(2, '0');
  return '${months[time.month - 1]} ${time.day}, ${time.year} · $hour:$minute ${time.hour < 12 ? 'AM' : 'PM'} PHT';
}

class _TaskPanel extends StatelessWidget {
  const _TaskPanel({required this.title, required this.child});
  final String title;
  final Widget child;
  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(title, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 14),
          child,
        ],
      ),
    ),
  );
}

class _TaskDetailLine extends StatelessWidget {
  const _TaskDetailLine({
    required this.icon,
    required this.label,
    required this.value,
  });
  final IconData icon;
  final String label, value;
  @override
  Widget build(BuildContext context) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Icon(icon, size: 20, color: Theme.of(context).colorScheme.primary),
      const SizedBox(width: 12),
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              value,
              style: Theme.of(context).textTheme.bodyMedium
                  ?.copyWith(fontWeight: FontWeight.w600),
            ),
          ],
        ),
      ),
    ],
  );
}

class _TaskFeedback extends StatelessWidget {
  const _TaskFeedback({required this.message, this.isError = false});
  final String message;
  final bool isError;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 8),
    child: Semantics(
      liveRegion: true,
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: isError
              ? Theme.of(context).colorScheme.errorContainer
              : Theme.of(context).colorScheme.primaryContainer,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              isError ? Icons.error_outline : Icons.check_circle_outline,
              size: 18,
              color: isError
                  ? Theme.of(context).colorScheme.onErrorContainer
                  : Theme.of(context).colorScheme.onPrimaryContainer,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                message,
                style: TextStyle(
                  color: isError
                      ? Theme.of(context).colorScheme.onErrorContainer
                      : Theme.of(context).colorScheme.onPrimaryContainer,
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

/// A protected keypad for Supervisor verification, separate from final approval.
class SupervisorConfirmPinSheet extends StatefulWidget {
  const SupervisorConfirmPinSheet({
    super.key,
    required this.client,
    required this.taskName,
    required this.onConfirm,
  });
  final SupabaseClient client;
  final String taskName;
  final Future<TaskRecord> Function(String pin) onConfirm;
  @override
  State<SupervisorConfirmPinSheet> createState() =>
      _SupervisorConfirmPinSheetState();
}

class _SupervisorConfirmPinSheetState extends State<SupervisorConfirmPinSheet>
    with WidgetsBindingObserver {
  String _pin = '';
  String? _error;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    AccessPolicy.of(widget.client).addListener(_accessChanged);
  }

  void _accessChanged() {
    final policy = AccessPolicy.of(widget.client);
    if (policy.enforced && !policy.verified && mounted) {
      setState(() => _pin = '');
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed && mounted && _pin.isNotEmpty) {
      setState(() => _pin = '');
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    AccessPolicy.of(widget.client).removeListener(_accessChanged);
    _pin = '';
    super.dispose();
  }

  void _press(String digit) {
    if (_busy) return;
    setState(() {
      _error = null;
      if (digit == 'Clear') {
        _pin = '';
      } else if (digit == 'Backspace') {
        if (_pin.isNotEmpty) _pin = _pin.substring(0, _pin.length - 1);
      } else if (_pin.length < 4) {
        _pin += digit;
      }
    });
  }

  Future<void> _confirm() async {
    if (_busy || _pin.length != 4) return;
    final pin = _pin;
    setState(() {
      _pin = '';
      _error = null;
      _busy = true;
    });
    try {
      final updated = await widget.onConfirm(pin);
      if (mounted) Navigator.pop(context, updated);
    } catch (error) {
      if (mounted) setState(() => _error = functionMessage(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return PopScope(
      canPop: !_busy,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.viewInsetsOf(context).bottom,
          ),
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 400),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            'Confirm work',
                            style: theme.textTheme.titleLarge,
                          ),
                        ),
                        IconButton(
                          tooltip: 'Close PIN entry',
                          onPressed: _busy
                              ? null
                              : () => Navigator.pop(context),
                          icon: const Icon(Icons.close),
                        ),
                      ],
                    ),
                    Text(widget.taskName, style: theme.textTheme.bodyMedium),
                    const SizedBox(height: 12),
                    Text('Supervisor PIN', style: theme.textTheme.titleMedium),
                    const SizedBox(height: 12),
                    Semantics(
                      label: '${_pin.length} of 4 PIN digits entered',
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: List.generate(
                          4,
                          (i) => Container(
                            width: 16,
                            height: 16,
                            margin: const EdgeInsets.symmetric(
                              horizontal: 11,
                              vertical: 8,
                            ),
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: i < _pin.length
                                  ? theme.colorScheme.primary
                                  : Colors.transparent,
                              border: Border.all(
                                color: theme.colorScheme.primary,
                                width: 1.6,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 14),
                    GridView.count(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      crossAxisCount: 3,
                      mainAxisExtent: 54,
                      mainAxisSpacing: 8,
                      crossAxisSpacing: 8,
                      children: [
                        for (final digit in [
                          '1',
                          '2',
                          '3',
                          '4',
                          '5',
                          '6',
                          '7',
                          '8',
                          '9',
                          'Clear',
                          '0',
                          'Backspace',
                        ])
                          OutlinedButton(
                            style: OutlinedButton.styleFrom(
                              padding: EdgeInsets.zero,
                            ),
                            onPressed: _busy ? null : () => _press(digit),
                            child: digit == 'Backspace'
                                ? const Icon(
                                    Icons.backspace_outlined,
                                    semanticLabel: 'Backspace',
                                  )
                                : Text(
                                    digit,
                                    style: TextStyle(
                                      fontSize: digit.length == 1 ? 22 : 13,
                                    ),
                                  ),
                          ),
                      ],
                    ),
                    if (_error != null) ...[
                      const SizedBox(height: 12),
                      _TaskFeedback(message: _error!, isError: true),
                    ],
                    const SizedBox(height: 16),
                    FilledButton(
                      onPressed: _busy || _pin.length != 4 ? null : _confirm,
                      child: Text(
                        _busy ? 'Confirming…' : 'Verify & confirm work',
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Final approval is a separate step.',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

String? fourDigits(String value) =>
    RegExp(r'^[0-9]{4}$').hasMatch(value) ? null : 'Enter exactly four digits.';
String? overrideReason(String value) => value.trim().length >= 10
    ? null
    : 'Explain the override using at least 10 characters.';

class EmployeePinPage extends StatefulWidget {
  const EmployeePinPage({super.key, required this.repo, required this.draft});
  final WorkRepository repo;
  final WorkDraft draft;
  @override
  State<EmployeePinPage> createState() => _EmployeePinPageState();
}

class _EmployeePinPageState extends State<EmployeePinPage>
    with WidgetsBindingObserver {
  String _pin = '';
  String? _error;
  bool _busy = false;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    AccessPolicy.of(widget.repo.client).addListener(_accessChanged);
  }

  void _accessChanged() {
    final policy = AccessPolicy.of(widget.repo.client);
    if (policy.enforced && !policy.verified && _pin.isNotEmpty && mounted) {
      setState(() => _pin = '');
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    AccessPolicy.of(widget.repo.client).removeListener(_accessChanged);
    _pin = '';
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed && _pin.isNotEmpty) {
      setState(() => _pin = '');
    }
  }

  Future<void> _confirm() async {
    if (_busy || _pin.length != 4) return;
    final pin = _pin;
    setState(() {
      _pin = '';
      _busy = true;
      _error = null;
    });
    try {
      final draft =
          await widget.repo.local.draft(widget.draft.task.id) ?? widget.draft;
      final accepted = await widget.repo.submit(draft, pin);
      if (mounted) Navigator.pop(context, accepted);
    } catch (error) {
      if (mounted) {
        setState(
          () => _error =
              '${functionMessage(error)} Your saved draft is retained. Reconnect and refresh the task if it changed.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_busy,
    child: Scaffold(
      appBar: AppBar(title: const Text('Confirm Completed Work')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                widget.draft.task.title,
                style: const TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.w700,
                ),
              ),
              Text(workTime(widget.draft.task.text('scheduled_at'))),
              Text(widget.draft.task.text('location')),
              const SizedBox(height: 24),
              const Text(
                'Enter Your 4-Digit PIN',
                style: TextStyle(fontSize: 20),
              ),
              Semantics(
                label: '${_pin.length} of four PIN digits entered',
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 24),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: List.generate(
                      4,
                      (i) => Text(
                        i < _pin.length ? '●' : '○',
                        style: const TextStyle(fontSize: 32),
                      ),
                    ),
                  ),
                ),
              ),
              GridView.count(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                crossAxisCount: 3,
                mainAxisExtent: MediaQuery.textScalerOf(context).scale(24) + 40,
                mainAxisSpacing: 8,
                crossAxisSpacing: 8,
                children:
                    [
                          '1',
                          '2',
                          '3',
                          '4',
                          '5',
                          '6',
                          '7',
                          '8',
                          '9',
                          'Clear',
                          '0',
                          'Backspace',
                        ]
                        .map(
                          (key) => OutlinedButton(
                            style: OutlinedButton.styleFrom(
                              padding: const EdgeInsets.all(4),
                            ),
                            onPressed: _busy
                                ? null
                                : () => setState(() {
                                    if (key == 'Clear') {
                                      _pin = '';
                                    } else if (key == 'Backspace') {
                                      if (_pin.isNotEmpty) {
                                        _pin = _pin.substring(
                                          0,
                                          _pin.length - 1,
                                        );
                                      }
                                    } else if (_pin.length < 4) {
                                      _pin += key;
                                    }
                                  }),
                            child: key == 'Backspace'
                                ? const Icon(
                                    Icons.backspace_outlined,
                                    semanticLabel: 'Backspace',
                                  )
                                : Text(
                                    key,
                                    style: TextStyle(
                                      fontSize: key.length == 1 ? 24 : 16,
                                    ),
                                  ),
                          ),
                        )
                        .toList(),
              ),
              const SizedBox(height: 24),
              FilledButton(
                onPressed: _busy || _pin.length != 4 ? null : _confirm,
                child: Text(_busy ? 'Confirming…' : 'Confirm Completed Task'),
              ),
              const SizedBox(height: 16),
              const Text(
                'Internet is required. Your PIN is never saved with offline drafts.',
              ),
              if (_error != null)
                Semantics(liveRegion: true, child: Text(_error!)),
            ],
          ),
        ),
      ),
    ),
  );
}
