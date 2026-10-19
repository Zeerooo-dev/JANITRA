import 'dart:async';

import 'package:flutter/foundation.dart';

import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import '../../core/access_notice.dart';
import '../../core/access_policy.dart';

import '../workspace/workspace_access.dart';
import 'local_work_store.dart';
import 'task_record.dart';

class WorkRepository {
  WorkRepository(this.client, {LocalWorkStore? local})
    : local = local ?? LocalWorkStore(client.auth.currentUser!.id);
  final SupabaseClient client;
  final LocalWorkStore local;
  bool cacheUnavailable = false;
  Future<List<Map<String, dynamic>>> rows(String table, {String? agencyId}) {
    AccessPolicy.of(client).requireVerified();
    return readWorkspaceRows(
      agencyId == null
          ? client.from(table).select()
          : client.from(table).select().eq('agency_id', agencyId),
    );
  }

  Future<List<TaskRecord>> tasks({String? agencyId}) async {
    final result = (await rows(
      'task_work_view',
      agencyId: agencyId,
    )).map(TaskRecord.new).toList();
    result.sort((a, b) => a.scheduledAt.compareTo(b.scheduledAt));
    // Cache writes must not hold the online workspace behind device storage.
    unawaited(
      local
          .put('personal_tasks', {
            'tasks': result
                .where((t) => t.userId == local.owner)
                .map((t) => t.cachedData)
                .toList(),
            'downloaded_at': DateTime.now().toUtc().toIso8601String(),
          })
          .catchError((Object _) {
            cacheUnavailable = true;
          }),
    );
    return result;
  }

  Future<List<Map<String, dynamic>>> personalSchedules() async {
    final shifts = (await rows('shift_templates'))
        .where((s) => s['user_id'] == local.owner)
        .toList();
    final ids = shifts.map((s) => s['id']).toSet();
    final segments = (await rows('shift_segments'))
        .where((s) => ids.contains(s['template_id']))
        .toList();
    final rules = (await rows('task_schedule_rules'))
        .where((s) => s['user_id'] == local.owner)
        .toList();
    try {
      await local.put('personal_schedules', {
        'shifts': shifts,
        'segments': segments,
        'rules': rules,
        'downloaded_at': DateTime.now().toUtc().toIso8601String(),
      });
    } catch (_) {
      cacheUnavailable = true;
    }
    return [
      for (final s in shifts)
        {
          ...s,
          'segments': segments
              .where((p) => p['template_id'] == s['id'])
              .toList(),
        },
    ];
  }

  Future<TaskRecord> task(String id) async {
    AccessPolicy.of(client).requireVerified();
    return TaskRecord(
      await client.from('task_work_view').select().eq('id', id).single(),
    );
  }

  Future<Map<String, dynamic>> command(
    String action,
    Map<String, dynamic> fields, {
    String? requestId,
  }) async {
    final response = await invokeProtected(
      client,
      'workflow',
      body: {
        ...fields,
        'action': action,
        'request_id': requestId ?? const Uuid().v4(),
      },
    );
    if (response.data is! Map || response.data['ok'] != true) {
      throw const FormatException('No server confirmation');
    }
    return Map<String, dynamic>.from(response.data as Map);
  }

  Future<WorkDraft> saveDraft(
    TaskRecord task,
    String remarks, {
    WorkDraft? previous,
    Map<String, bool> checklist = const {},
  }) async {
    if (task.userId != local.owner || task.effectiveStatus != 'SCHEDULED') {
      throw const FormatException(
        'Only your scheduled work can be saved as a draft',
      );
    }
    final draft = WorkDraft(
      task: task,
      remarks: remarks,
      checklist: Map.of(checklist),
      updatedAt: DateTime.now().toUtc().toIso8601String(),
      claimedAt:
          previous?.claimedAt ?? DateTime.now().toUtc().toIso8601String(),
      requestId:
          previous != null &&
              previous.task.version == task.version &&
              previous.task.checklistVersion == task.checklistVersion &&
              previous.remarks == remarks &&
              mapEquals(previous.checklist, checklist)
          ? previous.requestId
          : const Uuid().v4(),
    );
    await local.saveDraft(draft);
    return draft;
  }

  Future<TaskRecord> submit(WorkDraft draft, String pin) async {
    try {
      final result = await command('submit', {
        'task_id': draft.task.id,
        'version': draft.task.version,
        'remarks': draft.remarks,
        'claimed_at': draft.claimedAt,
        'pin': pin,
        if (draft.task.checklist.isNotEmpty)
          'checklist_results': draft.checklist,
        if (draft.task.checklist.isNotEmpty)
          'checklist_version': draft.task.checklistVersion,
      }, requestId: draft.requestId);
      final accepted = TaskRecord(
        Map<String, dynamic>.from(result['task'] as Map),
      );
      try {
        await local.remove('draft:${draft.task.id}');
      } catch (_) {
        cacheUnavailable = true;
      }
      return accepted;
    } on FunctionException catch (error) {
      final details = error.details;
      if (details is Map &&
          ['incorrect', 'locked', 'not_configured'].contains(details['code'])) {
        await local.saveDraft(
          WorkDraft(
            task: draft.task,
            remarks: draft.remarks,
            claimedAt: draft.claimedAt,
            requestId: const Uuid().v4(),
            checklist: draft.checklist,
            updatedAt: draft.updatedAt,
          ),
        );
      }
      rethrow;
    }
  }
}
