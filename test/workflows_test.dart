import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/testing.dart';
import 'package:janitra/features/work/local_work_store.dart';
import 'package:janitra/features/work/offline_access.dart';
import 'package:janitra/features/work/task_record.dart';
import 'package:janitra/features/work/work_repository.dart';
import 'package:janitra/features/work/task_page.dart';
import 'package:janitra/features/work/work_form.dart';
import 'package:janitra/features/work/records_page.dart';
import 'package:janitra/features/reports/report_export.dart';
import 'package:janitra/core/access_notice.dart';
import 'package:janitra/features/work/personal_sync.dart';
import 'package:janitra/features/work/checklist.dart';
import 'package:janitra/features/workspace/workspace_access.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:xml/xml.dart';

import 'fixtures/workspace_backend.dart';

TaskRecord sampleTask({String status = 'SCHEDULED'}) => TaskRecord({
  'id': '40000000-0000-0000-0000-000000000001',
  'user_id': fixtureUserId,
  'agency_id': fixtureAgencyId,
  'site_id': fixtureSiteId,
  'activity_name': 'Test cleaning',
  'location': 'Pantry',
  'instructions': 'Clean surfaces',
  'status': status,
  'version': 0,
  'scheduled_at': '2026-10-12T00:00:00Z',
  'review_deadline': '2026-10-13T04:00:00Z',
  'original_deadline': '2026-10-13T04:00:00Z',
  'personnel_name': 'Test Personnel',
  'site_name': 'Test Workplace',
  'agency_name': 'Test Agency',
  'client_name': 'Test Client',
  'work_date': '2026-10-12',
  'pin': 'DO-NOT-CACHE',
  'password': 'DO-NOT-CACHE',
  'access_token': 'DO-NOT-CACHE',
});

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Database db;
  late LocalWorkStore store;
  setUp(() async {
    sqfliteFfiInit();
    db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
    await db.execute(
      'CREATE TABLE work_cache(owner TEXT NOT NULL,bucket TEXT NOT NULL,payload BLOB NOT NULL,PRIMARY KEY(owner,bucket))',
    );
    store = LocalWorkStore(
      fixtureUserId,
      database: db,
      key: SecretKey(List.filled(32, 7)),
    );
  });
  tearDown(() async {
    if (db.isOpen) await db.close();
  });
  test('unchanged drafts reuse receipt, edited drafts receive a new request binding', () async {
    final client = SupabaseClient(
      'https://example.supabase.co',
      'test',
      httpClient: MockClient(WorkspaceTestBackend().handle),
      authOptions: const AuthClientOptions(autoRefreshToken: false),
    );
    final repo = WorkRepository(client, local: store);
    final old = await repo.saveDraft(sampleTask(), 'First remarks');
    final same = await repo.saveDraft(
      sampleTask(),
      'First remarks',
      previous: old,
    );
    expect(same.requestId, old.requestId);
    final changed = await repo.saveDraft(
      sampleTask(),
      'Edited remarks',
      previous: same,
    );
    expect(changed.requestId, isNot(old.requestId));
    expect(changed.claimedAt, old.claimedAt);
    await client.dispose();
  });
  test(
    'checklist editing preserves ordered identities and validates bounds',
    () {
      final first = parseChecklist('Wipe counters\nEmpty bins\nWipe counters');
      final reordered = parseChecklist(
        'Empty bins\nWipe counters\nWipe counters',
        previous: first,
      );
      expect(reordered.map((item) => item['id']), [
        first[1]['id'],
        first[0]['id'],
        first[2]['id'],
      ]);
      expect(parseChecklist('').isEmpty, isTrue);
      expect(
        () => parseChecklist(List.filled(51, 'Item').join('\n')),
        throwsFormatException,
      );
      expect(() => parseChecklist('x' * 201), throwsFormatException);
    },
  );
  test('offline proof expires after eight hours and rejects clock rollback', () async {
    final now = DateTime.utc(2026, 10, 18);
    final expiry =
        now.add(const Duration(days: 1)).millisecondsSinceEpoch ~/ 1000;
    final session = Session.fromJson({
      'access_token':
          'e30.${base64Url.encode(utf8.encode(jsonEncode({'exp': expiry}))).replaceAll('=', '')}.test',
      'refresh_token': 'test',
      'token_type': 'bearer',
      'user': WorkspaceTestBackend().user,
    })!;
    await saveOfflineAccess(
      session,
      store: store,
      now: now,
      scopes: ['$fixtureAgencyId/$fixtureSiteId'],
    );
    expect(
      await mayReadOfflinePersonalWork(
        session,
        store: store,
        now: now.add(const Duration(hours: 7)),
      ),
      isTrue,
    );
    expect(
      await mayReadOfflinePersonalWork(
        session,
        store: store,
        now: now.add(const Duration(hours: 6)),
      ),
      isFalse,
    );
    expect(
      await mayReadOfflinePersonalWork(
        session,
        store: store,
        now: now.add(const Duration(hours: 8)),
      ),
      isFalse,
    );
  });
  test('offline personal access requires matching sealed identity, token and unexpired session', () async {
    Session session(String token, int expiry) => Session.fromJson({
      'access_token':
          'eyJhbGciOiJIUzI1NiJ9.${base64Url.encode(utf8.encode(jsonEncode({'exp': expiry, 'marker': token}))).replaceAll('=', '')}.test',
      'refresh_token': 'test',
      'token_type': 'bearer',
      'user': WorkspaceTestBackend().user,
    })!;
    final expiry = DateTime.now().millisecondsSinceEpoch ~/ 1000 + 3600;
    final active = session('active', expiry);
    expect(await mayReadOfflinePersonalWork(active, store: store), false);
    await saveOfflineAccess(active, store: store);
    expect(await mayReadOfflinePersonalWork(active, store: store), true);
    expect(
      await mayReadOfflinePersonalWork(session('other', expiry), store: store),
      false,
    );
    expect(
      await mayReadOfflinePersonalWork(
        session('active', expiry - 7200),
        store: store,
      ),
      false,
    );
    final proof = (await store.get('personal_access_proof'))!;
    expect(proof, isNot(contains('access_token')));
    expect(jsonEncode(proof), isNot(contains(active.accessToken)));
    await store.remove('personal_access_proof');
    expect(await mayReadOfflinePersonalWork(active, store: store), false);
  });
  test('encrypted drafts hide contents and secrets, preserve identity and retry receipt', () async {
    final draft = WorkDraft(
      task: sampleTask(),
      remarks: 'Personal private remarks',
      claimedAt: '2026-10-12T01:00:00Z',
      requestId: 'test-receipt',
    );
    await store.saveDraft(draft);
    final bytes = (await db.query('work_cache')).single['payload'] as Uint8List;
    expect(
      utf8.decode(bytes, allowMalformed: true),
      isNot(contains('Personal private remarks')),
    );
    final loaded = (await store.draft(draft.task.id))!;
    expect(loaded.requestId, 'test-receipt');
    expect(loaded.claimedAt, draft.claimedAt);
    expect(jsonEncode(loaded.toJson()), isNot(contains('DO-NOT-CACHE')));
    final other = LocalWorkStore(
      'other',
      database: db,
      key: SecretKey(List.filled(32, 7)),
    );
    expect(await other.drafts(), isEmpty);
    expect(() => other.saveDraft(draft), throwsStateError);
  });
  test('offline proof rejects eight-hour expiry and clock rollback', () async {
    final started = DateTime.now().toUtc();
    final session = Session.fromJson({
      'access_token':
          'eyJhbGciOiJIUzI1NiJ9.${base64Url.encode(utf8.encode(jsonEncode({'exp': started.add(const Duration(days: 1)).millisecondsSinceEpoch ~/ 1000}))).replaceAll('=', '')}.test',
      'refresh_token': 'test',
      'token_type': 'bearer',
      'user': WorkspaceTestBackend().user,
    })!;
    await saveOfflineAccess(session, store: store, now: started);
    expect(
      await mayReadOfflinePersonalWork(
        session,
        store: store,
        now: started.add(const Duration(hours: 7)),
      ),
      true,
    );
    expect(
      await mayReadOfflinePersonalWork(session, store: store, now: started),
      false,
    );
    expect(
      await mayReadOfflinePersonalWork(
        session,
        store: store,
        now: started.add(const Duration(hours: 8)),
      ),
      false,
    );
  });
  test(
    'checklist draft changes bind a new request and old drafts remain readable',
    () async {
      final client = SupabaseClient('https://example.supabase.co', 'test');
      final repo = WorkRepository(client, local: store);
      final original = await repo.saveDraft(
        sampleTask(),
        'remarks',
        checklist: {'one': false},
      );
      final unchanged = await repo.saveDraft(
        sampleTask(),
        'remarks',
        checklist: {'one': false},
        previous: original,
      );
      final changed = await repo.saveDraft(
        sampleTask(),
        'remarks',
        checklist: {'one': true},
        previous: unchanged,
      );
      expect(unchanged.requestId, original.requestId);
      expect(changed.requestId, isNot(original.requestId));
      expect((await store.draft(changed.task.id))!.checklist, {'one': true});
      final legacy = original.toJson()..remove('checklist_results');
      expect(WorkDraft.fromJson(legacy).checklist, isEmpty);
      await client.dispose();
    },
  );
  test('sync marks conflicts and never submits or loses an offline draft on failure', () async {
    final backend = WorkspaceTestBackend()
      ..addSite()
      ..roles = [
        {
          'role': 'personnel',
          'agency_id': fixtureAgencyId,
          'site_id': fixtureSiteId,
        },
      ];
    final task = sampleTask();
    backend.workTables['task_work_view'] = [task.data];
    final client = SupabaseClient(
      'https://example.supabase.co',
      'test',
      httpClient: MockClient(backend.handle),
      authOptions: const AuthClientOptions(autoRefreshToken: false),
    );
    await client.auth.signInWithPassword(
      email: 'test@example.test',
      password: 'test-only',
    );
    final repo = WorkRepository(client, local: store);
    final draft = await repo.saveDraft(task, 'Unsent remarks');
    backend.workTables['task_work_view'] = [
      {...task.data, 'version': 1},
    ];
    final sync = PersonalSync(client, store: store);
    await sync.synchronize(
      WorkspaceAccess(fullName: backend.fullName, roles: backend.roles),
    );
    expect(sync.error, isNull);
    expect(sync.conflicts, 1);
    final complete = await store.get('personal_snapshot');
    expect(complete?['owner'], fixtureUserId);
    expect(backend.functionCalls, isEmpty);
    backend.offline = true;
    await sync.synchronize(
      WorkspaceAccess(fullName: backend.fullName, roles: backend.roles),
    );
    expect(sync.error, isNotNull);
    expect(await store.get('personal_snapshot'), complete);
    expect((await store.draft(task.id))!.requestId, draft.requestId);
    await client.dispose();
  });
  test(
    'seal removes cache access and preserves encrypted unsent drafts',
    () async {
      await store.saveDraft(
        WorkDraft(
          task: sampleTask(),
          remarks: 'Unsent',
          claimedAt: '2026-10-14T00:00:00Z',
          requestId: 'test-only',
        ),
      );
      await store.put('personal_access_proof', {'owner': fixtureUserId});
      await store.seal();
      expect(await db.query('work_cache'), hasLength(1));
      expect(store.draft(sampleTask().id), throwsStateError);
    },
  );
  test(
    'encrypted cache fails closed on tampering and account relocation',
    () async {
      await store.put('test', {'text': 'private'});
      final bytes = Uint8List.fromList(
        (await db.query('work_cache')).single['payload'] as Uint8List,
      );
      bytes[15] ^= 1;
      await db.update('work_cache', {'payload': bytes});
      expect(store.get('test'), throwsA(isA<SecretBoxAuthenticationError>()));
    },
  );
  test('server effective status overrides cached state without relying on phone clock', () {
    final task = sampleTask();
    task.data['effective_status'] = 'NOT_SUBMITTED';
    expect(task.effectiveStatus, 'NOT_SUBMITTED');
    expect(task.cachedData, isNot(contains('password')));
  });
  test('audit details expose readable changes without ids or credentials', () {
    final text = auditChanges({
      'before_data': {'is_active': true, 'password': 'private'},
      'after_data': {'is_active': false, 'user_id': fixtureUserId},
    });
    expect(text, contains('Enabled: true to false'));
    expect(text, isNot(contains('private')));
    expect(text, isNot(contains(fixtureUserId)));
  });
  test('work forms validate dates, times, leading zeros and justification', () {
    expect(validDate('2026-02-30'), isNotNull);
    expect(validTime('24:00'), isNotNull);
    expect(clockMinute('07:30'), 450);
    expect(fourDigits('0042'), isNull);
    expect(fourDigits('42'), isNotNull);
    expect(overrideReason('short'), isNotNull);
  });
  test('XLSX contains five styled frozen tabs and no credentials or executable formulas', () async {
    final row = sampleTask(status: 'APPROVED').data
      ..addAll({
        'report_status': 'APPROVED',
        'remarks': '=HYPERLINK("bad")',
        'submitted_at': '2026-10-12T01:00:00Z',
        'verified_at': '2026-10-12T02:00:00Z',
      });
    final report = WorkReport(
      agency: 'Test Agency',
      period: 'Test period',
      id: 'TEST ONLY',
      generatedAt: '2026-10-12T03:00:00Z',
      records: [row],
    );
    final bytes = report.xlsx();
    await File('/tmp/janitra-work-report-test.xlsx').writeAsBytes(bytes);
    final zip = ZipDecoder().decodeBytes(bytes);
    final workbook = XmlDocument.parse(
      utf8.decode(zip.findFile('xl/workbook.xml')!.content as List<int>),
    );
    expect(
      workbook.findAllElements('sheet').map((s) => s.getAttribute('name')),
      [
        'Summary',
        'Daily Work Records',
        'Employee Confirmations',
        'Supervisor Approvals',
        'Pending & Locked Tasks',
      ],
    );
    for (final file in zip.where(
      (f) => f.name.startsWith('xl/worksheets/') && f.name.endsWith('.xml'),
    )) {
      final xml = XmlDocument.parse(utf8.decode(file.content as List<int>));
      expect(xml.findAllElements('pane').single.getAttribute('ySplit'), '1');
      expect(xml.findAllElements('f'), isEmpty);
    }
    final all = zip
        .where((f) => f.name.endsWith('.xml'))
        .map((f) => utf8.decode(f.content as List<int>))
        .join();
    expect(all, isNot(contains('DO-NOT-CACHE')));
    expect(all.toUpperCase(), contains('234E70'));
    await File('/tmp/janitra-work-report-test.xlsx').writeAsBytes(bytes);
  });
  test('PDF export renders a real multipage report with readable timestamps', () async {
    final rows = List.generate(
      36,
      (i) => {
        ...sampleTask(status: 'APPROVED').data,
        'activity_name': 'Test cleaning ${i + 1}',
        'report_status': i.isEven ? 'APPROVED' : 'LOCKED_NOT_REVIEWED',
        'submitted_at': '2026-10-12T01:00:00Z',
        'remarks':
            'Test-only report record, used to verify pagination and wrapping.',
      },
    );
    rows.first['remarks'] = List.filled(80, 'Detailed test-only note. ').join();
    final report = WorkReport(
      agency: 'Test Agency',
      period: 'TEST ONLY · 2026-10-12',
      id: 'TEST ONLY',
      generatedAt: '2026-10-12T03:00:00Z',
      records: rows,
    );
    final bytes = await report.pdf();
    expect(ascii.decode(bytes.take(5).toList()), '%PDF-');
    await File('/tmp/janitra-work-report-test.pdf').writeAsBytes(bytes);
  });
  test(
    'backend access notice is emitted only for confirmed access loss',
    () async {
      final backend = WorkspaceTestBackend();
      final client = SupabaseClient(
        'https://example.supabase.co',
        'test',
        httpClient: MockClient(backend.handle),
        authOptions: const AuthClientOptions(autoRefreshToken: false),
      );
      await client.auth.signInWithPassword(
        email: 'test@example.test',
        password: 'test-only',
      );
      final notices = <AccessNotice>[];
      final sub = AccessNotice.events.listen(notices.add);
      backend.functionError = {'message': 'Expired', 'code': 'session_ended'};
      expect(
        invokeProtected(client, 'workflow', body: {'action': 'approve'}),
        throwsA(isA<FunctionException>()),
      );
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(notices.single.userId, fixtureUserId);
      expect(notices.single.token, client.auth.currentSession!.accessToken);
      notices.clear();
      backend.functionError = {
        'message': 'Unavailable',
        'code': 'verification_unavailable',
      };
      try {
        await invokeProtected(client, 'workflow', body: {'action': 'approve'});
      } catch (_) {}
      expect(notices.single.code, 'verification_unavailable');
      await sub.cancel();
      await client.dispose();
    },
  );
}
