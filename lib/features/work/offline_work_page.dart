import 'dart:async';

import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/access_policy.dart';
import 'offline_access.dart';
import 'personal_sync.dart';
import 'work_repository.dart';

import 'local_work_store.dart';
import 'task_record.dart';
import 'work_form.dart';
import 'personal_schedule_page.dart';

class OfflineWorkPage extends StatefulWidget {
  const OfflineWorkPage({super.key, required this.owner, required this.client});
  final String owner;
  final SupabaseClient client;
  @override
  State<OfflineWorkPage> createState() => _OfflineWorkPageState();
}

class _OfflineWorkPageState extends State<OfflineWorkPage>
    with WidgetsBindingObserver {
  Timer? _leaseTimer;
  late final store = LocalWorkStore(widget.owner);
  List<WorkDraft> _drafts = [];
  List<TaskRecord> _downloaded = [];
  List<Map<String, dynamic>> _shifts = [], _segments = [];
  bool _loading = true;
  String? _error, _notice;
  String? _lastSync;
  List<Map<String, dynamic>> _workplaces = [];
  Map<String, dynamic> _conflicts = {};
  late final sync = PersonalSync.of(widget.client);
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    sync.addListener(_syncChanged);
    _load();
  }

  void _syncChanged() {
    if (!sync.syncing && mounted) _load();
  }

  @override
  void dispose() {
    _leaseTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    sync.removeListener(_syncChanged);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _load();
  }

  Future<void> _checkAccess() async {
    final session = widget.client.auth.currentSession;
    if (session == null ||
        session.user.id != widget.owner ||
        !await mayReadOfflinePersonalWork(session)) {
      throw const AccessUnavailable();
    }
  }

  Future<void> _load() async {
    try {
      await _checkAccess();
      final drafts = await store.drafts();
      final snapshot = await store.get('personal_snapshot');
      final cached = snapshot ?? await store.get('personal_tasks');
      final schedules = snapshot ?? await store.get('personal_schedules');
      final proof = await store.get('personal_access_proof');
      if (!mounted) return;
      _leaseTimer?.cancel();
      final until = proof?['valid_until'] as int?;
      if (until != null) {
        final route = ModalRoute.of(context);
        final delay = DateTime.fromMillisecondsSinceEpoch(until)
            .difference(DateTime.now());
        _leaseTimer = Timer(delay.isNegative ? Duration.zero : delay, () {
          if (!mounted) return;
          Navigator.of(context)
              .popUntil((candidate) => candidate == route || candidate.isFirst);
          _load();
        });
      }
      final scopes = Set<String>.from(proof?['scopes'] as List? ?? []);
      await _checkAccess();
      if (mounted) {
        setState(() {
          _error = null;
          _drafts = drafts
              .where(
                (d) => scopes.contains('${d.task.agencyId}/${d.task.siteId}'),
              )
              .toList();
          _lastSync = snapshot?['downloaded_at'] as String?;
          _conflicts = Map<String, dynamic>.from(
            snapshot?['conflicts'] as Map? ?? {},
          );
          _workplaces = (snapshot?['workplaces'] as List? ?? [])
              .cast<Map<String, dynamic>>()
              .where((s) => scopes.contains('${s['agency_id']}/${s['id']}'))
              .toList();
          _shifts = (schedules?['shifts'] as List? ?? [])
              .cast<Map<String, dynamic>>()
              .where(
                (s) =>
                    s['user_id'] == widget.owner &&
                    scopes.contains(scopeKey(s)),
              )
              .toList();
          _segments = (schedules?['segments'] as List? ?? [])
              .cast<Map<String, dynamic>>();
          _downloaded = (cached?['tasks'] as List? ?? [])
              .map((t) => TaskRecord(Map<String, dynamic>.from(t as Map)))
              .where(
                (t) =>
                    t.userId == widget.owner &&
                    scopes.contains('${t.agencyId}/${t.siteId}'),
              )
              .toList();
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _drafts = [];
          _downloaded = [];
          _shifts = [];
          _segments = [];
          _workplaces = [];
          _conflicts = {};
          _error = 'Could not read saved work safely. Reconnect and download your tasks again.';
        });
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _edit(TaskRecord task) async {
    try {
      await _checkAccess();
    } catch (_) {
      await _load();
      return;
    }
    final old = _drafts.where((d) => d.task.id == task.id).firstOrNull;
    if (!mounted) return;
    await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => WorkForm(
        title: 'Save Offline Work',
        button: 'Save Draft',
        checklist: task.checklist,
        initialChecks: old?.checklist ?? const {},
        onDraftChanged: (values) => _preserve(task, values),
        fields: [
          WorkField(
            'remarks',
            'Optional remarks',
            optional: true,
            lines: 3,
            value: old?.remarks ?? '',
          ),
        ],
        save: (values) async {
          await _checkAccess();
          await _preserve(task, values);
          if (mounted) {
            setState(
              () => _notice = 'Saved Offline. Reconnect, refresh this task and enter your Employee PIN to submit.',
            );
          }
        },
      ),
    );
    if (mounted) await _load();
  }

  Future<void> _preserve(TaskRecord task, Map<String, dynamic> values) async {
    await _checkAccess();
    final previous = await store.draft(task.id);
    await WorkRepository(widget.client, local: store).saveDraft(
      task,
      values['remarks'] as String? ?? '',
      previous: previous,
      checklist: Map<String, bool>.from(
        values['checklist_results'] as Map? ?? {},
      ),
    );
  }

  Future<void> _resolve(WorkDraft draft) async {
    try {
      final fresh = await WorkRepository(widget.client).task(draft.task.id);
      if (!mounted) return;
      final yes = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Review updated task'),
          content: Text(
            '${fresh.title}\n${statusLabel(fresh.effectiveStatus)}\nYour remarks will be preserved. Review the latest checklist before an online PIN submission.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Keep old draft'),
            ),
            FilledButton(
              onPressed:
                  fresh.userId == widget.owner &&
                      fresh.effectiveStatus == 'SCHEDULED'
                  ? () => Navigator.pop(context, true)
                  : null,
              child: const Text('Use latest task'),
            ),
          ],
        ),
      );
      if (yes != true) return;
      await _checkAccess();
      await store.saveDraft(
        WorkDraft(
          task: fresh,
          remarks: draft.remarks,
          claimedAt: draft.claimedAt,
          requestId: const Uuid().v4(),
          checklist: {
            for (final item in fresh.checklist)
              item['id'] as String: draft.checklist[item['id']] ?? false,
          },
          updatedAt: DateTime.now().toUtc().toIso8601String(),
        ),
      );
      _conflicts.remove(draft.task.id);
      final snapshot = await store.get('personal_snapshot');
      if (snapshot != null) {
        await store.put('personal_snapshot', {
          ...snapshot,
          'conflicts': _conflicts,
        });
      }
      await _load();
    } catch (_) {
      if (mounted) {
        setState(
          () => _error = 'Reconnect and verify access to resolve this conflict. Your draft is preserved.',
        );
      }
    }
  }

  Future<void> _discardDraft(WorkDraft draft) async {
    final discard = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Discard saved draft?'),
        content: const Text(
          'This removes only the draft from this device. It does not change submitted work.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Keep draft'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Discard draft'),
          ),
        ],
      ),
    );
    if (discard != true) return;
    try {
      await _checkAccess();
      await store.remove('draft:${draft.task.id}');
      if (mounted) await _load();
    } catch (_) {
      if (mounted) await _load();
    }
  }

  Widget _heading(String title, {String? subtitle}) => Padding(
    padding: const EdgeInsets.fromLTRB(0, 16, 0, 10),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: Theme.of(context).textTheme.titleLarge),
        if (subtitle != null)
          Text(
            subtitle,
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
      ],
    ),
  );

  Widget _message(IconData icon, String message, {bool warning = false}) =>
      Card(
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                icon,
                size: 20,
                color: warning
                    ? Theme.of(context).colorScheme.error
                    : Theme.of(context).colorScheme.primary,
              ),
              const SizedBox(width: 10),
              Expanded(child: Text(message)),
            ],
          ),
        ),
      );

  Widget _draftCard(WorkDraft draft) {
    final conflict = _conflicts[draft.task.id] as Map?;
    final completed = draft.checklist.values.where((done) => done).length;
    final total = draft.task.checklist.length;
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 14, 10, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  conflict != null
                      ? Icons.warning_amber_rounded
                      : Icons.edit_note,
                  color: conflict != null
                      ? Theme.of(context).colorScheme.error
                      : Theme.of(context).colorScheme.primary,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        draft.task.title,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 3),
                      Text(
                        workTime(draft.task.text('scheduled_at')),
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: 'Discard draft',
                  onPressed: () => _discardDraft(draft),
                  icon: const Icon(Icons.delete_outline),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _offlineChip(
                  conflict != null ? 'Needs review' : 'Saved on device',
                  conflict != null
                      ? Icons.error_outline
                      : Icons.offline_pin_outlined,
                ),
                if (total > 0)
                  _offlineChip(
                    '$completed / $total checklist',
                    Icons.checklist_outlined,
                  ),
              ],
            ),
            if (conflict != null) ...[
              const SizedBox(height: 10),
              Text(
                conflict['reason']?.toString() ??
                    'The online task has changed.',
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ] else if (draft.remarks.trim().isNotEmpty) ...[
              const SizedBox(height: 10),
              Text(
                draft.remarks.trim(),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ],
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerRight,
              child: conflict != null
                  ? OutlinedButton.icon(
                      onPressed: () => _resolve(draft),
                      icon: const Icon(Icons.sync_problem, size: 18),
                      label: const Text('Review changes'),
                    )
                  : OutlinedButton.icon(
                      onPressed: () => _edit(draft.task),
                      icon: const Icon(Icons.edit_outlined, size: 18),
                      label: const Text('Edit draft'),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _offlineChip(String label, IconData icon) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
    decoration: BoxDecoration(
      color: Theme.of(context).colorScheme.primaryContainer,
      borderRadius: BorderRadius.circular(10),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          icon,
          size: 15,
          color: Theme.of(context).colorScheme.onPrimaryContainer,
        ),
        const SizedBox(width: 5),
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: Theme.of(context).colorScheme.onPrimaryContainer,
          ),
        ),
      ],
    ),
  );

  Widget _taskCard(TaskRecord task) => Card(
    child: ListTile(
      leading: Icon(
        Icons.assignment_outlined,
        color: Theme.of(context).colorScheme.primary,
      ),
      title: Text(task.title),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 4),
          Text(workTime(task.text('scheduled_at'))),
          Text(
            statusLabel(task.status),
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
      trailing: task.status == 'SCHEDULED'
          ? const Icon(Icons.chevron_right)
          : null,
      onTap: task.status == 'SCHEDULED' ? () => _edit(task) : null,
    ),
  );

  @override
  Widget build(BuildContext context) {
    final draftIds = _drafts.map((draft) => draft.task.id).toSet();
    final otherTasks = _downloaded
        .where((task) => !draftIds.contains(task.id))
        .toList();
    final scheduleCount = _shifts.length;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Saved Offline Work'),
        actions: [
          IconButton(
            tooltip: 'Refresh saved work',
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
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.fromLTRB(18, 10, 18, 28),
                  children: [
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Row(
                              children: [
                                Icon(
                                  Icons.cloud_done_outlined,
                                  color: Theme.of(context).colorScheme.primary,
                                  size: 25,
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: AnimatedBuilder(
                                    animation: sync,
                                    builder: (context, _) => Text(
                                      AccessPolicy.of(widget.client).verified
                                          ? sync.status
                                          : 'Offline · online actions paused',
                                      style: Theme.of(context)
                                          .textTheme
                                          .titleMedium,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 6),
                            Text(
                              _lastSync == null
                                  ? 'No downloaded snapshot yet'
                                  : 'Last synced ${workTime(_lastSync)}',
                              style: TextStyle(
                                color: Theme.of(context)
                                    .colorScheme
                                    .onSurfaceVariant,
                              ),
                            ),
                            const SizedBox(height: 14),
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: [
                                _offlineChip(
                                  '${_drafts.length} drafts',
                                  Icons.edit_note,
                                ),
                                _offlineChip(
                                  '${_conflicts.length} conflicts',
                                  Icons.warning_amber_outlined,
                                ),
                                _offlineChip(
                                  '${_downloaded.length} tasks',
                                  Icons.assignment_outlined,
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),
                            Align(
                              alignment: Alignment.centerLeft,
                              child: TextButton.icon(
                                onPressed: AccessPolicy.of(widget.client).retry,
                                icon: const Icon(Icons.sync_outlined, size: 18),
                                label: const Text('Verify & sync'),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    if (_error != null)
                      _message(Icons.error_outline, _error!, warning: true),
                    if (_notice != null)
                      _message(Icons.check_circle_outline, _notice!),
                    _heading(
                      'Saved drafts',
                      subtitle: 'Not submitted until you confirm online',
                    ),
                    if (_drafts.isEmpty)
                      _message(
                        Icons.edit_note,
                        'No drafts saved on this device.',
                      ),
                    for (final draft in _drafts) _draftCard(draft),
                    _heading(
                      'Downloaded tasks',
                      subtitle: 'Tasks available in your device snapshot',
                    ),
                    if (otherTasks.isEmpty)
                      _message(
                        Icons.assignment_outlined,
                        _downloaded.isEmpty ? 'No tasks downloaded yet.' : 'Your downloaded tasks are shown in Saved drafts.',
                      ),
                    for (final task in otherTasks) _taskCard(task),
                    if (scheduleCount > 0) ...[
                      _heading('Downloaded schedule'),
                      for (final shift in _shifts)
                        ScheduleShiftCard(
                          shift: shift,
                          segments: _segments
                              .where((p) => p['template_id'] == shift['id'])
                              .toList(),
                        ),
                    ],
                    if (_workplaces.isNotEmpty) ...[
                      _heading('Workplaces'),
                      Card(
                        child: Column(
                          children: [
                            for (final site in _workplaces)
                              ListTile(
                                dense: true,
                                leading: Icon(
                                  Icons.place_outlined,
                                  color: Theme.of(context).colorScheme.primary,
                                ),
                                title: Text(
                                  site['name']?.toString() ?? 'Workplace',
                                ),
                              ),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
              ),
      ),
    );
  }
}
