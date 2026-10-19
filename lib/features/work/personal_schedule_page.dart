import 'package:flutter/material.dart';

import '../../core/app_theme.dart';
import 'work_repository.dart';

class PersonalSchedulePage extends StatefulWidget {
  const PersonalSchedulePage({super.key, required this.repo});
  final WorkRepository repo;
  @override
  State<PersonalSchedulePage> createState() => _PersonalSchedulePageState();
}

class _PersonalSchedulePageState extends State<PersonalSchedulePage> {
  List<Map<String, dynamic>> _shifts = [];
  String? _error;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final shifts = await widget.repo.personalSchedules();
      if (mounted) {
        setState(() {
          _shifts = shifts;
          _error = null;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(
          () => _error = 'Could not refresh your schedule. Check your connection and retry.',
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('My Work Schedule'),
      actions: [
        IconButton(
          tooltip: 'Refresh schedule',
          onPressed: _loading ? null : _load,
          icon: const Icon(Icons.refresh),
        ),
      ],
    ),
    body: SafeArea(
      child: _loading && _shifts.isEmpty
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(18, 12, 18, 28),
                children: [
                  Row(
                    children: [
                      Icon(
                        Icons.calendar_month_outlined,
                        color: Theme.of(context).colorScheme.primary,
                        size: 26,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Assigned shifts',
                              style: Theme.of(context).textTheme.titleLarge,
                            ),
                            Text(
                              _shifts.isEmpty
                                  ? 'Your weekly work hours'
                                  : '${_shifts.where((s) => s['is_active'] == true).length} active of ${_shifts.length} assigned',
                              style: TextStyle(
                                color: Theme.of(context)
                                    .colorScheme
                                    .onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  if (_error != null)
                    _ScheduleNotice(
                      icon: Icons.wifi_off_outlined,
                      message: _error!,
                      action: TextButton.icon(
                        onPressed: _loading ? null : _load,
                        icon: const Icon(Icons.refresh, size: 18),
                        label: const Text('Retry'),
                      ),
                    ),
                  if (_shifts.isEmpty && _error == null)
                    const _ScheduleNotice(
                      icon: Icons.event_available,
                      message: 'No shifts assigned yet. Your schedule will appear here when your supervisor adds one.',
                    ),
                  for (final shift in _shifts)
                    ScheduleShiftCard(
                      shift: shift,
                      segments: (shift['segments'] as List? ?? const []),
                    ),
                  if (widget.repo.cacheUnavailable)
                    const _ScheduleNotice(
                      icon: Icons.phonelink_erase,
                      message: 'Schedule displayed, but a device copy could not be saved.',
                    ),
                ],
              ),
            ),
    ),
  );
}

class _ScheduleNotice extends StatelessWidget {
  const _ScheduleNotice({
    required this.icon,
    required this.message,
    this.action,
  });
  final IconData icon;
  final String message;
  final Widget? action;

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          Icon(icon, color: Theme.of(context).colorScheme.onSurfaceVariant),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [Text(message), if (action != null) action!],
            ),
          ),
        ],
      ),
    ),
  );
}

/// Used by both the online schedule and the downloaded offline schedule.
/// This is presentation-only: no authorization or synchronization is changed.
class ScheduleShiftCard extends StatelessWidget {
  const ScheduleShiftCard({
    super.key,
    required this.shift,
    required this.segments,
  });
  final Map<String, dynamic> shift;
  final List segments;

  static const _days = ['', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

  String _date(BuildContext context, Object? value) {
    if (value == null || value.toString().isEmpty) return 'Ongoing';
    final parsed = DateTime.tryParse(value.toString());
    return parsed == null
        ? value.toString()
        : MaterialLocalizations.of(context).formatMediumDate(parsed);
  }

  String _clock(Object? value) {
    if (value is! int) return '—';
    final hours = value ~/ 60 % 24;
    final minutes = value % 60;
    final text =
        '${hours.toString().padLeft(2, '0')}:${minutes.toString().padLeft(2, '0')}';
    return value >= 1440 ? '$text +1 day' : text;
  }

  @override
  Widget build(BuildContext context) {
    final active = shift['is_active'] == true;
    final weekdays = (shift['weekdays'] as List? ?? const [])
        .whereType<int>()
        .where((day) => day >= 1 && day <= 7)
        .toSet();
    final name = shift['name']?.toString() ?? 'Work shift';
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.access_time_outlined,
                  color: Theme.of(context).colorScheme.primary,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    name,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 9,
                    vertical: 5,
                  ),
                  decoration: BoxDecoration(
                    color: active
                        ? const Color(0xFFEDF7F1)
                        : const Color(0xFFF2F3F5),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    active ? 'Active' : 'Paused',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: active ? const Color(0xFF216E4B) : janitraMuted,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (var i = 1; i <= 7; i++)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 9,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: weekdays.contains(i)
                          ? Theme.of(context).colorScheme.primaryContainer
                          : Theme.of(context).colorScheme.surfaceContainerLow,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      _days[i],
                      style: TextStyle(
                        fontWeight: weekdays.contains(i)
                            ? FontWeight.w700
                            : FontWeight.w400,
                        fontSize: 12,
                        color: weekdays.contains(i)
                            ? Theme.of(context).colorScheme.onPrimaryContainer
                            : Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Icon(
                  Icons.date_range_outlined,
                  size: 17,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '${_date(context, shift['starts_on'])} – ${_date(context, shift['ends_on'])}',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ],
            ),
            if (segments.isNotEmpty) ...[
              const Divider(height: 26),
              for (final raw in segments)
                if (raw is Map)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Row(
                      children: [
                        Icon(
                          raw['kind'] == 'break'
                              ? Icons.free_breakfast_outlined
                              : Icons.work_outline,
                          size: 18,
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            raw['kind'] == 'break' ? 'Break' : 'Work',
                          ),
                        ),
                        Expanded(
                          child: Text(
                            '${_clock(raw['start_minute'])} – ${_clock(raw['end_minute'])}',
                            textAlign: TextAlign.end,
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                        ),
                      ],
                    ),
                  ),
            ],
          ],
        ),
      ),
    );
  }
}

// Preserve this formatting helper for existing integrations.
String scheduleDescription(Map<String, dynamic> shift, List segments) {
  String clock(int minute) =>
      '${(minute ~/ 60 % 24).toString().padLeft(2, '0')}:${(minute % 60).toString().padLeft(2, '0')}${minute >= 1440 ? ' next day' : ''}';
  const days = ['', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
  return '${(shift['weekdays'] as List).map((d) => days[d as int]).join(', ')}\n${shift['starts_on']} to ${shift['ends_on'] ?? 'ongoing'} · ${shift['is_active'] == true ? 'Active' : 'Paused'}\n${segments.map((s) => '${s['kind'] == 'break' ? 'Break' : 'Work'} ${clock(s['start_minute'] as int)} to ${clock(s['end_minute'] as int)}').join('\n')}';
}
