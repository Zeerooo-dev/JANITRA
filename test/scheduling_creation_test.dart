import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:janitra/core/app_theme.dart';
import 'package:janitra/features/work/scheduling_page.dart';
import 'package:janitra/features/work/work_form.dart';
import 'package:janitra/features/workspace/workspace_access.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'fixtures/workspace_backend.dart';

const otherAgency = '10000000-0000-0000-0000-000000000002';
const otherSite = '30000000-0000-0000-0000-000000000002';
const personnel = '00000000-0000-0000-0000-000000000002';

void main() {
  setUpAll(() async {
    await (FontLoader('Roboto')
          ..addFont(rootBundle.load('assets/fonts/Roboto-Regular.ttf'))
          ..addFont(rootBundle.load('assets/fonts/Roboto-Bold.ttf')))
        .load();
    await (FontLoader(
      'MaterialIcons',
    )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
  });
  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 4; i++) {
      await tester.pump();
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 30)),
      );
    }
    await tester.pumpAndSettle();
  }

  Finder add(String section) => find.descendant(
    of: find.widgetWithText(SectionHeading, section),
    matching: find.byType(TextButton),
  );
  Future<void> show(
    WidgetTester tester,
    Finder finder, {
    double delta = 180,
  }) async {
    await tester.scrollUntilVisible(
      finder,
      delta,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
  }

  Future<void> choose(
    WidgetTester tester,
    Finder dropdown,
    String label,
  ) async {
    await tester.ensureVisible(dropdown);
    await tester.tap(dropdown);
    await tester.pumpAndSettle();
    await tester.tap(find.text(label).last);
    await settle(tester);
  }

  Future<void> switchCompany(
    WidgetTester tester,
    String current,
    String name,
  ) async {
    final selector = find.byKey(ValueKey('scheduling-company/$current'));
    await show(tester, selector, delta: -220);
    await choose(tester, selector, name);
  }

  Future<void> save(WidgetTester tester) async {
    await tester.tap(find.text('Save'));
    await settle(tester);
  }

  Future<WorkspaceTestBackend> open(
    WidgetTester tester, {
    String role = 'supervisor',
    bool homePersonnel = false,
  }) async {
    final backend = WorkspaceTestBackend()..addSite();
    backend.agencies.first['name'] = 'Cleaners';
    backend.agencies.add({'id': otherAgency, 'name': 'LSERVE Corp.'});
    backend.sites.add({
      'id': otherSite,
      'agency_id': otherAgency,
      'name': 'Other Workplace',
    });
    backend.roles = [
      {
        'role': role == 'site-specific' ? 'supervisor' : role,
        'agency_id': role == 'admin' ? null : fixtureAgencyId,
        'site_id': role == 'site-specific' || role == 'personnel'
            ? fixtureSiteId
            : null,
      },
    ];
    backend.managedUsers.addAll([
      {
        'user_id': personnel,
        'agency_id': homePersonnel ? fixtureAgencyId : otherAgency,
        'site_id': homePersonnel ? fixtureSiteId : otherSite,
        'role': 'personnel',
        'full_name': 'Test Personnel',
        'is_active': true,
      },
      {
        'user_id': 'inactive-person',
        'agency_id': otherAgency,
        'site_id': otherSite,
        'role': 'personnel',
        'full_name': 'Inactive Personnel',
        'is_active': false,
      },
      {
        'user_id': 'unscoped-person',
        'agency_id': otherAgency,
        'site_id': 'unavailable-site',
        'role': 'personnel',
        'full_name': 'Unavailable workplace',
        'is_active': true,
      },
      {
        'user_id': 'supervisor-person',
        'agency_id': otherAgency,
        'site_id': null,
        'role': 'supervisor',
        'full_name': 'Other Supervisor',
        'is_active': true,
      },
    ]);
    for (final table in [
      'work_activities',
      'shift_templates',
      'task_schedule_rules',
      'shift_segments',
      'schedule_exceptions',
      'deadline_policies',
    ]) {
      backend.workTables[table] = [];
    }
    backend.workTables['work_activities']!.add({
      'id': '40000000-0000-0000-0000-000000000001',
      'agency_id': fixtureAgencyId,
      'site_id': fixtureSiteId,
      'name': 'Cleaners activity',
      'location': '',
      'is_active': true,
    });
    final client = (await tester.runAsync(
      () async => SupabaseClient(
        'https://example.supabase.co',
        'test',
        authOptions: const AuthClientOptions(autoRefreshToken: false),
        httpClient: MockClient((request) async {
          if (!request.url.path.endsWith('/workflow')) {
            return backend.handle(request);
          }
          final body = jsonDecode(request.body) as Map<String, dynamic>;
          backend.functionCalls.add(body);
          if (backend.functionError != null) {
            return http.Response(
              jsonEncode(backend.functionError),
              400,
              headers: {'content-type': 'application/json'},
            );
          }
          final table = switch (body['action']) {
            'activity_save' => 'work_activities',
            'shift_save' => 'shift_templates',
            'rule_save' => 'task_schedule_rules',
            _ => throw StateError('Unexpected workflow action'),
          };
          final id = switch (table) {
            'work_activities' => '40000000-0000-0000-0000-000000000009',
            'shift_templates' => '50000000-0000-0000-0000-000000000009',
            _ => '60000000-0000-0000-0000-000000000009',
          };
          backend.workTables[table]!.add({...body, 'id': id});
          return http.Response(
            jsonEncode({'ok': true, 'id': id}),
            200,
            headers: {'content-type': 'application/json'},
          );
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
        theme: janitraTheme(),
        home: SchedulingPage(
          client: client,
          access: WorkspaceAccess(
            fullName: 'Test manager',
            roles: backend.roles,
          ),
          agencyId: fixtureAgencyId,
          sites: backend.sites
              .where((s) => s['agency_id'] == fixtureAgencyId)
              .toList(),
        ),
      ),
    );
    await settle(tester);
    return backend;
  }

  for (final role in ['admin', 'supervisor']) {
    testWidgets(
      '$role selects the correct company and saves work shifts and cleaning schedules',
      (tester) async {
        final backend = await open(tester, role: role);
        await show(tester, add('Work shifts'));
        expect(tester.widget<TextButton>(add('Work shifts')).onPressed, isNull);
        expect(
          find.textContaining(
            'No active Personnel assigned to your workplaces in Cleaners.',
          ),
          findsWidgets,
        );
        await switchCompany(tester, fixtureAgencyId, 'LSERVE Corp.');
        await show(tester, add('Cleaning schedules'));
        expect(
          tester.widget<TextButton>(add('Cleaning schedules')).onPressed,
          isNull,
        );
        expect(
          find.textContaining('Create an enabled activity'),
          findsOneWidget,
        );
        await show(tester, add('Work shifts'), delta: -180);
        expect(
          tester.widget<TextButton>(add('Work shifts')).onPressed,
          isNotNull,
        );
        await tester.tap(add('Work shifts'));
        await tester.pumpAndSettle();
        final reads = backend.requests.length;
        await save(tester);
        expect(
          backend.functionCalls.where((c) => c['action'] == 'shift_save'),
          isEmpty,
        );
        expect(find.byType(CircularProgressIndicator), findsNothing);
        await tester.tap(find.text('Cancel'));
        await tester.pumpAndSettle();
        expect(backend.requests.length, reads);
        await tester.tap(add('Work shifts'));
        await tester.pumpAndSettle();
        Finder dropdowns() => find.descendant(
          of: find.byType(WorkForm),
          matching: find.byType(DropdownButtonFormField<String>),
        );
        await choose(
          tester,
          dropdowns().first,
          'Test Personnel · Other Workplace',
        );
        expect(find.textContaining('Inactive Personnel'), findsNothing);
        expect(find.textContaining('Unavailable workplace'), findsNothing);
        await save(tester);
        final shift = backend.functionCalls.singleWhere(
          (c) => c['action'] == 'shift_save',
        );
        expect(shift['agency_id'], otherAgency);
        expect(shift['site_id'], otherSite);
        expect(shift['user_id'], personnel);
        expect(shift['weekdays'], [1, 2, 3, 4, 5, 6]);
        expect(shift['segments'], [
          {'start': 420, 'end': 720, 'kind': 'work'},
          {'start': 960, 'end': 1200, 'kind': 'work'},
        ]);
        expect(shift['is_active'], isTrue);
        expect(find.byType(WorkForm), findsNothing);

        await show(tester, add('Cleaning activities'), delta: -180);
        await tester.tap(add('Cleaning activities'));
        await tester.pumpAndSettle();
        await choose(tester, dropdowns().first, 'Other Workplace');
        await tester.enterText(
          find.byType(TextFormField).first,
          'Clean LSERVE',
        );
        await save(tester);
        await show(tester, add('Cleaning schedules'));
        expect(
          tester.widget<TextButton>(add('Cleaning schedules')).onPressed,
          isNotNull,
        );
        await tester.tap(add('Cleaning schedules'));
        await tester.pumpAndSettle();
        await choose(
          tester,
          dropdowns().at(1),
          'Test Personnel · Other Workplace',
        );
        await choose(tester, dropdowns().at(2), 'Clean LSERVE');
        await choose(tester, dropdowns().at(3), 'Work schedule');
        await save(tester);
        final rule = backend.functionCalls.singleWhere(
          (c) => c['action'] == 'rule_save',
        );
        expect(rule['agency_id'], otherAgency);
        expect(rule['site_id'], otherSite);
        expect(rule['user_id'], personnel);
        expect(rule['activity_id'], '40000000-0000-0000-0000-000000000009');
        expect(rule['shift_id'], '50000000-0000-0000-0000-000000000009');
        expect(rule['at_minute'], 480);
        expect(rule['until_minute'], 480);
        expect(rule['interval_minutes'], isNull);
        expect(find.byType(WorkForm), findsNothing);
        expect(backend.workTables['task_schedule_rules'], hasLength(1));
        expect(
          backend.roles.single['agency_id'],
          role == 'admin' ? null : fixtureAgencyId,
        );
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'Site-Specific Supervisor can create shifts and cleaning schedules at the assigned workplace',
    (tester) async {
      final backend = await open(
        tester,
        role: 'site-specific',
        homePersonnel: true,
      );
      for (final section in ['Work shifts', 'Cleaning schedules']) {
        await show(tester, add(section));
        await tester.tap(add(section));
        await tester.pumpAndSettle();
        final dropdowns = find.descendant(
          of: find.byType(WorkForm),
          matching: find.byType(DropdownButtonFormField<String>),
        );
        await choose(
          tester,
          dropdowns.at(section == 'Work shifts' ? 0 : 1),
          'Test Personnel · Test Workplace',
        );
        if (section == 'Cleaning schedules') {
          await choose(tester, dropdowns.at(2), 'Cleaners activity');
        }
        await save(tester);
        expect(find.byType(WorkForm), findsNothing);
      }
      final writes = backend.functionCalls
          .where((c) => c['action'] != 'list')
          .toList();
      expect(writes.map((c) => c['action']), ['shift_save', 'rule_save']);
      expect(
        writes.every(
          (c) =>
              c['agency_id'] == fixtureAgencyId &&
              c['site_id'] == fixtureSiteId &&
              c['user_id'] == personnel,
        ),
        isTrue,
      );
    },
  );

  testWidgets(
    'rejected shift save stays editable and retries without reporting false success',
    (tester) async {
      final backend = await open(tester, role: 'admin', homePersonnel: true);
      await show(tester, add('Work shifts'));
      await tester.tap(add('Work shifts'));
      await tester.pumpAndSettle();
      await choose(
        tester,
        find
            .descendant(
              of: find.byType(WorkForm),
              matching: find.byType(DropdownButtonFormField<String>),
            )
            .first,
        'Test Personnel · Test Workplace',
      );
      final reads = backend.requests.length;
      backend.functionError = {'message': 'Could not save this schedule.'};
      await save(tester);
      expect(find.byType(WorkForm), findsOneWidget);
      expect(find.text('Could not save this schedule.'), findsOneWidget);
      expect(backend.workTables['shift_templates'], isEmpty);
      expect(backend.requests.length, reads);
      backend.functionError = null;
      await save(tester);
      expect(find.byType(WorkForm), findsNothing);
      expect(backend.workTables['shift_templates'], hasLength(1));
    },
  );

  testWidgets(
    'company context and scheduling form fit a 320px phone with 200 percent text',
    (tester) async {
      tester.view.physicalSize = const Size(320, 844);
      tester.view.devicePixelRatio = 1;
      tester.platformDispatcher.textScaleFactorTestValue = 2;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      final backend = await open(tester);
      await expectLater(
        find.byType(Scaffold).first,
        matchesGoldenFile('goldens/scheduling-company-large-text.png'),
      );
      await switchCompany(tester, fixtureAgencyId, 'LSERVE Corp.');
      await show(tester, add('Work shifts'));
      await tester.tap(add('Work shifts'));
      await tester.pumpAndSettle();
      await choose(
        tester,
        find
            .descendant(
              of: find.byType(WorkForm),
              matching: find.byType(DropdownButtonFormField<String>),
            )
            .first,
        'Test Personnel · Other Workplace',
      );
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(
        backend.functionCalls.where((c) => c['action'] != 'list'),
        isEmpty,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'Site-Specific Supervisor cannot select foreign companies or their Personnel',
    (tester) async {
      final backend = await open(tester, role: 'site-specific');
      expect(find.byType(DropdownButtonFormField<String>), findsNothing);
      expect(find.text('Cleaners'), findsOneWidget);
      expect(find.text('LSERVE Corp.'), findsNothing);
      await show(tester, add('Work shifts'));
      expect(tester.widget<TextButton>(add('Work shifts')).onPressed, isNull);
      expect(
        backend.functionCalls.where((c) => c['action'] != 'list'),
        isEmpty,
      );
    },
  );
}
