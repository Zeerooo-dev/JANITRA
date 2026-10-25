import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/app_theme.dart';
import '../../core/aurora_glass.dart';
import '../workspace/workspace_access.dart';
import 'task_record.dart';
import 'work_repository.dart';
import 'task_page.dart';

class WorkOverview extends StatefulWidget {
  const WorkOverview({
    super.key,
    required this.client,
    required this.access,
    required this.agencyId,
  });
  final SupabaseClient client;
  final WorkspaceAccess access;
  final String? agencyId;
  @override
  State<WorkOverview> createState() => _WorkOverviewState();
}

class _WorkOverviewState extends State<WorkOverview>
    with WidgetsBindingObserver {
  List<TaskRecord> _tasks = [];
  bool _loading = true, _fetching = false;
  String? _error;
  DateTime? _lastRefresh;
  bool get supervisor =>
      widget.agencyId != null &&
      widget.access.supervisesAgency(widget.agencyId!);
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _load();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  Future<void> _load() async {
    if (_fetching) return;
    _fetching = true;
    try {
      final tasks = await WorkRepository(widget.client)
          .tasks(agencyId: widget.agencyId);
      if (mounted) {
        setState(() {
          _tasks = tasks;
          _error = null;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'Could not load work. Reconnect and retry.');
      }
    } finally {
      _fetching = false;
      _lastRefresh = DateTime.now();
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed &&
        (_lastRefresh == null ||
            DateTime.now().difference(_lastRefresh!) >
                const Duration(seconds: 10))) {
      _load();
    }
  }

  Future<void> _all() async {
    await Navigator.push(
      context,
      MaterialPageRoute<void>(
        builder: (_) => TasksPage(
          client: widget.client,
          access: widget.access,
          agencyId: widget.agencyId,
        ),
      ),
    );
    if (mounted) await _load();
  }

  Future<void> _details(TaskRecord task) async {
    await Navigator.push(
      context,
      MaterialPageRoute<void>(
        builder: (_) => TaskDetailsPage(
          repo: WorkRepository(widget.client),
          task: task,
          access: widget.access,
        ),
      ),
    );
    if (mounted) await _load();
  }

  Widget _metric(String label, int value) => JanitraGlassCard(
    child: Padding(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            '$value',
            style: const TextStyle(fontSize: 27, fontWeight: FontWeight.w700),
          ),
        ],
      ),
    ),
  );
  @override
  Widget build(BuildContext context) {
    final today = _tasks
        .where((t) => t.text('work_date') == dateOnly(manilaNow()))
        .toList();
    final next = today
        .where(
          (t) =>
              t.effectiveStatus == 'SCHEDULED' &&
              t.userId == widget.client.auth.currentUser?.id,
        )
        .firstOrNull;
    final pending = _tasks
        .where(
          (t) => [
            'PENDING_APPROVAL',
            'REOPENED_FOR_REVIEW',
          ].contains(t.effectiveStatus),
        )
        .toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (_loading)
          const LinearProgressIndicator(semanticsLabel: 'Loading daily work'),
        if (_error != null) ...[
          Text(_error!),
          TextButton(onPressed: _load, child: const Text('Retry Work')),
        ] else if (!_loading && supervisor) ...[
          LayoutBuilder(
            builder: (context, constraints) {
              final cards = [
                _metric(
                  'Pending Verification',
                  pending.where((t) => !t.verified).length,
                ),
                _metric(
                  'Pending Approval',
                  pending.where((t) => t.verified).length,
                ),
              ];
              return constraints.maxWidth < 330 ||
                      MediaQuery.textScalerOf(context).scale(16) > 22
                  ? Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: cards,
                    )
                  : IntrinsicHeight(
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Expanded(child: cards[0]),
                          const SizedBox(width: 12),
                          Expanded(child: cards[1]),
                        ],
                      ),
                    );
            },
          ),
          const SectionHeading('Needs review'),
          if (pending.isEmpty)
            const JanitraEmptyState(
              'All caught up. No tasks awaiting review.',
              icon: Icons.check_circle_outline,
            ),
          for (final task in pending.take(3))
            JanitraGlassCard(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(14, 12, 14, 10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            task.text('personnel_name'),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        WorkStatusBadge(
                          label: task.verified ? 'Approval' : 'Confirmation',
                          status: task.effectiveStatus,
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      task.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 3),
                    Text(
                      workTime(task.text('scheduled_at')),
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                        fontSize: 13,
                      ),
                    ),
                    Align(
                      alignment: Alignment.centerRight,
                      child: TextButton.icon(
                        onPressed: () => _details(task),
                        icon: const Icon(Icons.arrow_forward, size: 17),
                        label: const Text('Review Task'),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          if (_tasks.any((t) => t.effectiveStatus == 'LOCKED_NOT_REVIEWED'))
            Text(
              'Locked work: ${_tasks.where((t) => t.effectiveStatus == 'LOCKED_NOT_REVIEWED').length}',
            ),
          TextButton(onPressed: _all, child: const Text('View All Tasks')),
        ] else if (!_loading) ...[
          Text(
            'Today · ${today.where((t) => t.submittedAtText.isNotEmpty).length} '
            'of ${today.where((t) => t.status != 'CANCELLED').length} submitted',
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
              fontSize: 14,
            ),
          ),
          const SizedBox(height: 16),
          if (next == null)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 16),
              child: Text('No next cleaning task is assigned today.'),
            )
          else
            JanitraGlassCard(
              child: Padding(
                padding: const EdgeInsets.all(18),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      'YOUR NEXT TASK',
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      next.title,
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const Divider(),
                    Text(
                      workTime(next.text('scheduled_at')),
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      next.text('location'),
                      style: const TextStyle(fontSize: 18),
                    ),
                    const SizedBox(height: 16),
                    FilledButton(
                      onPressed: () => _details(next),
                      child: const Text('Mark as Done'),
                    ),
                  ],
                ),
              ),
            ),
          const SizedBox(height: 12),
          OutlinedButton(
            onPressed: _all,
            child: const Text('View All My Tasks'),
          ),
        ],
      ],
    );
  }
}
