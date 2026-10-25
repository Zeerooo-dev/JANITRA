import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/access_notice.dart';
import '../../core/aurora_glass.dart';

import '../work/work_repository.dart';
import '../work/task_record.dart';
import '../work/work_form.dart';
import '../workspace/function_message.dart';
import 'report_export.dart';

class ReportsPage extends StatefulWidget {
  const ReportsPage({
    super.key,
    required this.client,
    required this.agencyId,
    required this.agencyName,
    required this.sites,
    this.embedded = false,
  });
  final SupabaseClient client;
  final bool embedded;
  final String agencyId, agencyName;
  final List<Map<String, dynamic>> sites;
  @override
  State<ReportsPage> createState() => _ReportsPageState();
}

class _ReportsPageState extends State<ReportsPage> {
  late final repo = WorkRepository(widget.client);
  List<Map<String, dynamic>> _people = [];
  String? _error, _notice;
  bool _busy = false;
  @override
  void initState() {
    super.initState();
    _loadPeople();
  }

  Future<void> _loadPeople() async {
    try {
      final r = await invokeProtected(
        widget.client,
        'manage-users',
        body: {'action': 'list', 'agency_id': widget.agencyId},
      );
      if (mounted) {
        setState(
          () => _people = (r.data['users'] as List)
              .cast<Map<String, dynamic>>()
              .where(
                (p) =>
                    p['agency_id'] == null || p['agency_id'] == widget.agencyId,
              )
              .toList(),
        );
      }
    } catch (e) {
      if (mounted) setState(() => _error = functionMessage(e));
    }
  }

  Future<void> _export(String period, String format) async {
    final now = manilaNow();
    var from = DateTime(now.year, now.month, now.day),
        until = DateTime(now.year, now.month, now.day);
    if (period == 'Weekly') {
      from = from.subtract(Duration(days: from.weekday - 1));
      until = from.add(const Duration(days: 6));
    }
    if (period == 'Monthly') {
      from = DateTime(now.year, now.month);
      until = DateTime(now.year, now.month + 1, 0);
    }
    await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => WorkForm(
        title: '$period $format Report',
        button: 'Generate Report',
        fields: [
          WorkField(
            'from_date',
            'From date (YYYY-MM-DD)',
            value: dateOnly(from),
            validate: validDate,
          ),
          WorkField(
            'to_date',
            'Through date (YYYY-MM-DD)',
            value: dateOnly(until),
            validate: validDate,
          ),
          WorkField(
            'site_id',
            'Workplace (optional)',
            optional: true,
            choices: {
              for (final s in widget.sites)
                s['id'] as String: s['name'] as String,
            },
          ),
          WorkField(
            'user_id',
            'Personnel (optional)',
            optional: true,
            choices: {
              for (final p in _people.where((p) => p['role'] == 'personnel'))
                p['user_id'] as String: p['full_name'] as String,
            },
          ),
          WorkField(
            'supervisor_id',
            'Supervisor (optional)',
            optional: true,
            choices: {
              for (final p in _people.where((p) => p['role'] == 'supervisor'))
                p['user_id'] as String: p['full_name'] as String,
            },
          ),
          WorkField(
            'status',
            'Approval status (optional)',
            optional: true,
            choices: {
              for (final s in [
                'SCHEDULED',
                'PENDING_APPROVAL',
                'APPROVED',
                'REJECTED',
                'LOCKED_NOT_REVIEWED',
                'REOPENED_FOR_REVIEW',
                'NOT_SUBMITTED',
                'CANCELLED',
              ])
                s: statusLabel(s),
            },
          ),
        ],
        save: (fields) async {
          if (mounted) setState(() => _busy = true);
          try {
            final response = await repo.command('report', {
              'agency_id': widget.agencyId,
              'format': format.toLowerCase(),
              ...fields,
            });
            final rows = (response['records'] as List)
                .cast<Map<String, dynamic>>();
            final report = WorkReport(
              agency: widget.agencyName,
              period: '${fields['from_date']} to ${fields['to_date']}',
              id: response['report_id'] as String,
              generatedAt: response['generated_at'] as String,
              records: rows,
            );
            final bytes = format == 'PDF' ? await report.pdf() : report.xlsx();
            final file = File(
              '${(await getApplicationDocumentsDirectory()).path}/JANITRA-${response['report_id']}.${format.toLowerCase()}',
            );
            await file.writeAsBytes(bytes, flush: true);
            await SharePlus.instance.share(
              ShareParams(
                files: [XFile(file.path)],
                text: 'JANITRA authorized work report',
                sharePositionOrigin: const Rect.fromLTWH(0, 0, 1, 1),
              ),
            );
            if (mounted) {
              setState(
                () => _notice = rows.isEmpty
                    ? 'Empty report generated: no matching authorized work records.'
                    : 'Report generated from ${rows.length} authorized work records.',
              );
            }
          } finally {
            if (mounted) setState(() => _busy = false);
          }
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: widget.embedded ? Colors.transparent : null,
    appBar: widget.embedded ? null : AppBar(title: const Text('Work Reports')),
    body: SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            JanitraGlassCard(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Icon(
                      Icons.assessment_outlined,
                      size: 36,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      widget.agencyName,
                      style: const TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      'Choose a period to export work records as PDF or Excel. Filter by workplace, personnel, supervisor, or status. Internet is required.',
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),
            for (final period in ['Weekly', 'Monthly', 'Custom'])
              Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: OutlinedButton(
                  onPressed: _busy
                      ? null
                      : () async {
                          final format = await showModalBottomSheet<String>(
                            context: context,
                            builder: (context) => SafeArea(
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  ListTile(
                                    title: const Text('PDF Work Report'),
                                    onTap: () => Navigator.pop(context, 'PDF'),
                                  ),
                                  ListTile(
                                    title: const Text('Excel Work Report'),
                                    onTap: () => Navigator.pop(context, 'XLSX'),
                                  ),
                                ],
                              ),
                            ),
                          );
                          if (format != null && mounted) {
                            await _export(period, format);
                          }
                        },
                  child: Text('$period Report'),
                ),
              ),
            if (_notice != null)
              Semantics(liveRegion: true, child: Text(_notice!)),
            if (_error != null) ...[
              Semantics(liveRegion: true, child: Text(_error!)),
              TextButton(
                onPressed: _loadPeople,
                child: const Text('Retry People Filters'),
              ),
            ],
          ],
        ),
      ),
    ),
  );
}
