import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/access_policy.dart';
import '../workspace/workspace_access.dart';
import 'local_work_store.dart';
import 'task_record.dart';
import 'offline_access.dart';

String scopeKey(Map<String, dynamic> role) =>
    '${role['agency_id']}/${role['site_id']}';
String? draftConflict(WorkDraft draft, TaskRecord? fresh) {
  if (fresh == null) {
    return 'This task is no longer available in your assignment.';
  }
  if (fresh.userId != draft.task.userId ||
      fresh.agencyId != draft.task.agencyId ||
      fresh.siteId != draft.task.siteId) {
    return 'The workplace assignment changed.';
  }
  if (fresh.effectiveStatus != 'SCHEDULED') {
    return 'This task is ${statusLabel(fresh.effectiveStatus).toLowerCase()}. It cannot be submitted from this draft.';
  }
  if (fresh.version != draft.task.version ||
      fresh.checklistVersion != draft.task.checklistVersion) {
    return 'The task or checklist changed. Review the latest version before submitting.';
  }
  return null;
}

class PersonalSync extends ChangeNotifier {
  PersonalSync(this.client, {LocalWorkStore? store}) : _injected = store;
  static final _instances = Expando<PersonalSync>();
  static PersonalSync of(SupabaseClient client) =>
      _instances[client] ??= PersonalSync(client);
  final SupabaseClient client;
  final LocalWorkStore? _injected;
  Future<void>? _running;
  String? owner, error, lastSync;
  int pending = 0, conflicts = 0;
  bool get syncing => _running != null;
  String get status => syncing
      ? 'Synchronizing…'
      : error != null
      ? 'Sync failed. Saved work is preserved.'
      : lastSync == null
      ? 'Not synchronized yet'
      : 'Synchronized';

  Future<void> synchronize(WorkspaceAccess access) {
    if (_running != null) return _running!;
    final session = client.auth.currentSession;
    if (session == null) return Future.error(const AccessUnavailable());
    if (owner != session.user.id) {
      owner = session.user.id;
      lastSync = null;
      pending = 0;
      conflicts = 0;
    }
    final running = _synchronize(access, session);
    _running = running.whenComplete(() {
      _running = null;
      notifyListeners();
    });
    notifyListeners();
    return _running!;
  }

  Future<void> _synchronize(WorkspaceAccess access, Session session) async {
    final local = _injected ?? LocalWorkStore(session.user.id);
    void current() {
      AccessPolicy.of(client).requireVerified();
      if (client.auth.currentSession?.accessToken != session.accessToken ||
          client.auth.currentUser?.id != session.user.id) {
        throw const AccessUnavailable();
      }
    }

    try {
      current();
      final scopes = access.roles
          .where((r) => r['role'] == 'personnel')
          .map(scopeKey)
          .toSet();
      if (scopes.isEmpty) return;
      Future<List<Map<String, dynamic>>> own(String table) => readWorkspaceRows(
        client.from(table).select().eq('user_id', session.user.id),
      );
      final tasks = (await own('task_work_view'))
          .map(TaskRecord.new)
          .where(
            (t) =>
                t.userId == session.user.id &&
                scopes.contains('${t.agencyId}/${t.siteId}'),
          )
          .toList();
      current();
      final shifts = (await own('shift_templates'))
          .where((s) => scopes.contains(scopeKey(s)))
          .toList();
      final ids = shifts.map((s) => s['id'] as String).toList();
      final segments = ids.isEmpty
          ? <Map<String, dynamic>>[]
          : await readWorkspaceRows(
              client
                  .from('shift_segments')
                  .select()
                  .inFilter('template_id', ids),
            );
      final rules = (await own('task_schedule_rules'))
          .where((r) => scopes.contains(scopeKey(r)))
          .toList();
      current();
      final siteIds = access.roles
          .where((r) => r['role'] == 'personnel')
          .map((r) => r['site_id'] as String)
          .toSet()
          .toList();
      final sites = await readWorkspaceRows(
        client
            .from('sites')
            .select('id,agency_id,name,client_company_id')
            .inFilter('id', siteIds),
      );
      final freshRoles = (await readWorkspaceRows(
        client
            .from('role_assignments')
            .select('role,agency_id,site_id')
            .eq('user_id', session.user.id)
            .eq('is_active', true),
      )).where((r) => r['role'] == 'personnel').map(scopeKey).toSet();
      current();
      if (!setEquals(scopes, freshRoles)) throw const AccessUnavailable();
      final drafts = await local.drafts();
      final issues = <String, dynamic>{};
      for (final d in drafts) {
        final fresh = tasks.where((t) => t.id == d.task.id).firstOrNull;
        final reason = draftConflict(d, fresh);
        if (reason != null) {
          issues[d.task.id] = {
            'reason': reason,
            if (fresh != null) 'fresh_task': fresh.cachedData,
          };
        }
      }
      final timestamp = DateTime.now().toUtc().toIso8601String();
      current();
      await local.put('personal_snapshot', {
        'schema': 2,
        'owner': session.user.id,
        'scopes': scopes.toList(),
        'tasks': tasks.map((t) => t.cachedData).toList(),
        'shifts': shifts,
        'segments': segments,
        'rules': rules,
        'workplaces': sites,
        'downloaded_at': timestamp,
        'conflicts': issues,
      });
      current();
      await saveOfflineAccess(session, store: local, scopes: scopes.toList());
      pending = drafts.length;
      conflicts = issues.length;
      lastSync = timestamp;
      error = null;
    } catch (failure) {
      error = failure is AccessUnavailable
          ? failure.toString()
          : 'Could not synchronize. Reconnect and retry.';
    }
  }
}
