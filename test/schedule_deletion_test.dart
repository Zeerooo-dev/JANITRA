import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:janitra/features/work/scheduling_page.dart';
import 'package:janitra/features/workspace/workspace_access.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'fixtures/workspace_backend.dart';

const activityId = '40000000-0000-0000-0000-000000000021';
const shiftId = '50000000-0000-0000-0000-000000000021';
const ruleId = '60000000-0000-0000-0000-000000000021';

void main() {
  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 4; i++) {
      await tester.pump();
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 30)),
      );
    }
    await tester.pumpAndSettle();
  }

  Future<WorkspaceTestBackend> open(
    WidgetTester tester, {
    bool personnel = false,
    required Future<http.Response?> Function(Map<String, dynamic>) delete,
  }) async {
    final backend = WorkspaceTestBackend()..addSite();
    final scope = {'agency_id': fixtureAgencyId, 'site_id': fixtureSiteId};
    backend.workTables.addAll({
      'work_activities': [
        {
          ...scope,
          'id': activityId,
          'name': 'Test activity',
          'location': 'Pantry',
        },
      ],
      'shift_templates': [
        {...scope, 'id': shiftId, 'name': 'Test shift'},
      ],
      'task_schedule_rules': [
        {
          ...scope,
          'id': ruleId,
          'activity_id': activityId,
          'shift_id': shiftId,
          'at_minute': 480,
        },
      ],
      'shift_segments': [],
      'schedule_exceptions': [],
      'deadline_policies': [],
    });
    backend.managedUsers.add({
      ...scope,
      'user_id': fixtureUserId,
      'role': 'personnel',
      'full_name': 'Test Personnel',
      'is_active': true,
    });
    final client = (await tester.runAsync(
      () async => SupabaseClient(
        'https://example.supabase.co',
        'test',
        authOptions: const AuthClientOptions(autoRefreshToken: false),
        httpClient: MockClient((request) async {
          final table = request.url.path.split('/').last;
          if (request.method == 'GET' &&
              backend.workTables.containsKey(table)) {
            backend.requests.add(request);
            return http.Response(
              jsonEncode(backend.workTables[table]),
              200,
              request: request,
              headers: {
                'content-type': 'application/json',
                'content-range': backend.workTables[table]!.isEmpty
                    ? '*/0'
                    : '0-${backend.workTables[table]!.length - 1}/${backend.workTables[table]!.length}',
              },
            );
          }
          if (request.url.path.endsWith('/workflow')) {
            final body = jsonDecode(request.body) as Map<String, dynamic>;
            backend.functionCalls.add(body);
            final failure = await delete(body);
            if (failure != null) return failure;
            switch (body['action']) {
              case 'activity_delete':
                backend.workTables['work_activities']!.clear();
                backend.workTables['task_schedule_rules']!.clear();
              case 'shift_delete':
                backend.workTables['shift_templates']!.clear();
                backend.workTables['task_schedule_rules']!.clear();
              case 'rule_delete':
                backend.workTables['task_schedule_rules']!.clear();
            }
            return http.Response(
              '{"ok":true,"deleted":true}',
              200,
              headers: {'content-type': 'application/json'},
            );
          }
          return backend.handle(request);
        }),
      ),
    ))!;
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox());
      await tester.runAsync(client.dispose);
    });
    await tester.runAsync(
      () => client.auth.signInWithPassword(
        email: 'test@example.test',
        password: 'test-only',
      ),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: SchedulingPage(
          client: client,
          access: WorkspaceAccess(
            fullName: 'Test user',
            roles: personnel
                ? [
                    {
                      'role': 'personnel',
                      'agency_id': fixtureAgencyId,
                      'site_id': fixtureSiteId,
                    },
                  ]
                : backend.roles,
          ),
          agencyId: fixtureAgencyId,
          sites: backend.sites,
        ),
      ),
    );
    await settle(tester);
    expect(
      find.text('Test activity'),
      findsWidgets,
      reason: tester
          .widgetList<Text>(find.byType(Text))
          .map((text) => text.data)
          .join(' | '),
    );
    return backend;
  }

  for (final kind in ['activity', 'work shift', 'cleaning schedule']) {
    testWidgets(
      'Supervisor deletes $kind only after confirmation; Cancel does not reload',
      (tester) async {
        if (kind == 'cleaning schedule') {
          tester.view.physicalSize = const Size(320, 640);
          tester.view.devicePixelRatio = 1;
          tester.platformDispatcher.textScaleFactorTestValue = 2;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
        }
        final backend = await open(tester, delete: (_) async => null);
        final initialRequests = backend.requests.length;
        final button = find.byTooltip('Delete $kind');
        await tester.scrollUntilVisible(button, 180);
        await tester.pumpAndSettle();
        await tester.tap(button);
        await tester.pumpAndSettle();
        expect(
          find.textContaining('Submitted work and history will be kept.'),
          findsOneWidget,
        );
        await tester.tap(find.text('Cancel'));
        await tester.pump();
        expect(find.byType(CircularProgressIndicator), findsNothing);
        await settle(tester);
        expect(backend.requests.length, initialRequests);
        expect(
          backend.functionCalls.where(
            (call) => call['action'].toString().endsWith('_delete'),
          ),
          isEmpty,
        );
        await tester.scrollUntilVisible(button, 180);
        await tester.pumpAndSettle();
        await tester.tap(button);
        await tester.pumpAndSettle();
        await tester.tap(find.text('Delete'));
        await settle(tester);
        final deletion = backend.functionCalls.lastWhere(
          (call) => call['action'].toString().endsWith('_delete'),
        );
        expect(deletion['action'], switch (kind) {
          'activity' => 'activity_delete',
          'work shift' => 'shift_delete',
          _ => 'rule_delete',
        });
        expect(deletion['id'], switch (kind) {
          'activity' => activityId,
          'work shift' => shiftId,
          _ => ruleId,
        });
        expect(deletion['agency_id'], fixtureAgencyId);
        expect(deletion['site_id'], fixtureSiteId);
        expect(deletion['request_id'], isA<String>());
        expect(find.byTooltip('Delete $kind'), findsNothing);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'failed deletion keeps the row and retries with the same request',
    (tester) async {
      var attempts = 0;
      final backend = await open(
        tester,
        delete: (_) async => ++attempts == 1
            ? http.Response(
                '{"message":"Test deletion failed"}',
                400,
                headers: {'content-type': 'application/json'},
              )
            : null,
      );
      await tester.tap(find.byTooltip('Delete activity'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delete'));
      await settle(tester);
      expect(backend.workTables['work_activities'], hasLength(1));
      expect(find.text('Test deletion failed'), findsOneWidget);
      await tester.tap(find.text('Delete'));
      await settle(tester);
      final requests = backend.functionCalls
          .where((call) => call['action'] == 'activity_delete')
          .toList();
      expect(requests, hasLength(2));
      expect(requests.first['request_id'], requests.last['request_id']);
      expect(find.byTooltip('Delete activity'), findsNothing);
    },
  );

  testWidgets('Personnel have no scheduling deletion controls', (tester) async {
    await open(tester, personnel: true, delete: (_) async => null);
    expect(find.byIcon(Icons.delete_outline), findsNothing);
  });
}
