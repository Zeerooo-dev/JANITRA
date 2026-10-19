import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/testing.dart';
import 'package:janitra/app.dart';
import 'package:janitra/features/workspace/workspace_access.dart';
import 'package:janitra/features/workspace/name_editor.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'fixtures/workspace_backend.dart';

void main() {
  Future<SupabaseClient> open(
    WidgetTester tester,
    WorkspaceTestBackend backend,
  ) async {
    final client = (await tester.runAsync(
      () async => SupabaseClient(
        'https://example.supabase.co',
        'sb_publishable_test',
        httpClient: MockClient(backend.handle),
        authOptions: const AuthClientOptions(autoRefreshToken: false),
      ),
    ))!;
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox());
      await tester.runAsync(client.dispose);
    });
    await tester.runAsync(
      () => client.auth.signInWithPassword(
        email: 'worker@example.test',
        password: 'test-session-only',
      ),
    );
    await tester.pumpWidget(JanitraApp(client: client));
    await tester.pumpAndSettle();
    return client;
  }

  Future<void> nav(WidgetTester tester, String label) async {
    if (label == 'Profile' || label == 'Workplaces') {
      await tester.tap(find.byTooltip(label).first);
      await tester.pumpAndSettle();
      return;
    }
    await tester.tap(
      find.descendant(
        of: find.byType(NavigationBar),
        matching: find.text(label),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> tap(WidgetTester tester, Finder finder) async {
    await tester.ensureVisible(finder);
    await tester.tap(finder);
    await tester.pumpAndSettle();
  }

  Future<void> tapFunction(WidgetTester tester, Finder finder) async {
    await tester.ensureVisible(finder);
    await tester.tap(finder);
    // FunctionsClient encodes and decodes JSON in a real isolate.
    for (var i = 0; i < 4; i++) {
      await tester.pump();
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
    }
    await tester.pumpAndSettle();
  }

  test('management rights remain scoped to agency and site', () {
    final access = WorkspaceAccess(
      fullName: 'Test',
      roles: [
        {'role': 'supervisor', 'agency_id': 'a', 'site_id': 'site-a'},
        {'role': 'personnel', 'agency_id': 'b', 'site_id': 'site-b'},
      ],
    );
    expect(access.isSupervisor, isTrue);
    expect(access.managesAgency('a'), isFalse);
    expect(access.managesAgency('b'), isFalse);
    expect(access.managesSite({'id': 'site-a', 'agency_id': 'a'}), isTrue);
    expect(access.managesSite({'id': 'other', 'agency_id': 'a'}), isFalse);
    expect(access.managesSite({'id': 'site-b', 'agency_id': 'b'}), isFalse);
  });

  test('Admin management scope is global and site-specific Supervisors remain scoped', () {
    const access = WorkspaceAccess(
      fullName: 'Admin',
      roles: [
        {'role': 'admin', 'agency_id': null, 'site_id': null},
      ],
    );
    expect(access.isAdmin, isTrue);
    expect(access.isSupervisor, isTrue);
    expect(access.managesAgency('any-agency'), isTrue);
    expect(
      access.managesSite({'id': 'any-site', 'agency_id': 'any-agency'}),
      isTrue,
    );
  });

  test(
    'Company-Wide Supervisor manages all companies without becoming Admin',
    () {
      const access = WorkspaceAccess(
        fullName: 'Company Supervisor',
        roles: [
          {'role': 'supervisor', 'agency_id': fixtureAgencyId, 'site_id': null},
        ],
      );
      expect(access.isAdmin, isFalse);
      expect(access.isCompanyWideSupervisor, isTrue);
      expect(access.supervisesAgency('other-company'), isTrue);
      expect(access.managesAgency('other-company'), isTrue);
      expect(
        access.managesSite({'id': 'other-site', 'agency_id': 'other-company'}),
        isTrue,
      );
    },
  );

  testWidgets(
    'Company-Wide Supervisor switches companies and manages their workplaces',
    (tester) async {
      final backend = WorkspaceTestBackend()..addSite();
      const other = '10000000-0000-0000-0000-000000000002';
      backend.agencies.add({'id': other, 'name': 'A Other Company'});
      backend.clients.add({
        'id': 'other-client',
        'agency_id': other,
        'name': 'Other Client',
      });
      backend.sites.add({
        'id': 'other-site',
        'agency_id': other,
        'client_company_id': 'other-client',
        'name': 'Other Workplace',
      });
      await open(tester, backend);
      final selector = find.byType(DropdownButtonFormField<String>);
      expect(
        tester.widget<DropdownButtonFormField<String>>(selector).initialValue,
        fixtureAgencyId,
      );
      await tap(tester, selector);
      await tap(tester, find.text('A Other Company').last);
      await nav(tester, 'Workplaces');
      expect(find.text('Other Workplace'), findsOneWidget);
      expect(find.byTooltip('Add Client Company'), findsOneWidget);
      expect(find.byTooltip('Add Workplace'), findsOneWidget);
      await nav(tester, 'Profile');
      await tap(tester, find.byTooltip('Edit company A Other Company'));
      await tester.enterText(
        find.byType(TextFormField),
        'Renamed Other Company',
      );
      await tap(tester, find.text('Save changes'));
      expect(backend.writes.last.url.queryParameters['id'], 'eq.$other');
      expect(jsonDecode(backend.writes.last.body), {
        'name': 'Renamed Other Company',
      });
      expect(backend.roles.single['agency_id'], fixtureAgencyId);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'Company-Wide Supervisor creates and selects a manpower agency without refreshing access',
    (tester) async {
      final backend = WorkspaceTestBackend()..addSite();
      await open(tester, backend);
      await nav(tester, 'Profile');
      final add = find.text('Add Manpower Agency');
      await tester.scrollUntilVisible(
        add,
        180,
        scrollable: find.byType(Scrollable).last,
      );
      await tap(tester, add);
      final before = backend.requests.length;
      await tap(tester, find.text('Save'));
      expect(backend.requests.length, before);
      expect(find.byType(CircularProgressIndicator), findsNothing);
      await tap(tester, find.text('Cancel'));
      expect(backend.requests.length, before);
      await tap(tester, add);
      await tester.enterText(
        find.byType(TextFormField).first,
        '  LSERVE Corp.  ',
      );
      await tester.enterText(find.byType(TextFormField).last, 'test-password');
      final profileReads = backend.requests
          .where((r) => r.url.path.endsWith('/profiles'))
          .length;
      await tapFunction(tester, find.text('Save'));
      expect(
        backend.functionCalls
            .where((c) => c['action'] == 'create_agency')
            .single,
        {
          'action': 'create_agency',
          'agency_id': fixtureAgencyId,
          'name': 'LSERVE Corp.',
          'password': 'test-password',
        },
      );
      expect(
        backend.requests.where((r) => r.url.path.endsWith('/profiles')).length,
        profileReads,
      );
      final selector = find.byType(DropdownButtonFormField<String>);
      expect(
        tester.widget<DropdownButtonFormField<String>>(selector).initialValue,
        '10000000-0000-0000-0000-000000000009',
      );
      await tap(tester, selector);
      expect(find.text('Test Manpower'), findsWidgets);
      await tap(tester, find.text('LSERVE Corp.').last);
      await nav(tester, 'Workplaces');
      expect(find.byTooltip('Add Client Company'), findsOneWidget);
      expect(backend.roles.single['agency_id'], fixtureAgencyId);
      await tapFunction(
        tester,
        find.descendant(
          of: find.byType(NavigationBar),
          matching: find.text('Team'),
        ),
      );
      expect(find.text('Supervisor Management'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  for (final role in ['admin', 'supervisor', 'personnel']) {
    testWidgets('$role agency creation visibility respects authority', (
      tester,
    ) async {
      final backend = WorkspaceTestBackend()..addSite();
      backend.roles = [
        {
          'role': role,
          'agency_id': role == 'admin' ? null : fixtureAgencyId,
          'site_id': role == 'admin' ? null : fixtureSiteId,
        },
      ];
      await open(tester, backend);
      await nav(tester, 'Profile');
      await tester.drag(find.byType(Scrollable).last, const Offset(0, -700));
      await tester.pumpAndSettle();
      expect(
        find.text('Add Manpower Agency'),
        role == 'admin' ? findsOneWidget : findsNothing,
      );
      expect(backend.writes, isEmpty);
      expect(
        backend.functionCalls.where((c) => c['action'] == 'create_agency'),
        isEmpty,
      );
    });
  }

  testWidgets(
    'global Admin reuses dashboard and can invite a site-specific Supervisor',
    (tester) async {
      final backend = WorkspaceTestBackend()..addSite();
      backend.roles = [
        {'role': 'admin', 'agency_id': null, 'site_id': null},
      ];
      await open(tester, backend);
      expect(find.text('Account connected'), findsNothing);
      await tapFunction(tester, find.text('Team'));
      await tapFunction(tester, find.text('Supervisor Management'));
      await tap(tester, find.text('Add person'));
      expect(find.text('Unique username'), findsNothing);
      await tap(tester, find.text('Company-Wide'));
      await tap(tester, find.text('Site-Specific').last);
      await tester.enterText(
        find.byType(TextFormField).at(0),
        'Site Supervisor',
      );
      await tester.enterText(
        find.byType(TextFormField).at(1),
        'manager@example.test',
      );
      await tester.enterText(find.byType(TextFormField).last, 'test-password');
      await tap(tester, find.text('Send invite'));
      expect(find.text('Select at least one workplace.'), findsOneWidget);
      expect(
        backend.functionCalls.where((c) => c['action'] == 'invite'),
        isEmpty,
      );
      await tap(tester, find.text('Test Workplace'));
      await tapFunction(tester, find.text('Send invite'));
      final invite = backend.functionCalls.lastWhere(
        (c) => c['action'] == 'invite',
      );
      expect(invite['role'], 'supervisor');
      expect(invite['site_ids'], [fixtureSiteId]);
      expect(invite['site_id'], isNull);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('restored Supervisor opens dashboard and can sign out', (
    tester,
  ) async {
    final backend = WorkspaceTestBackend();
    final client = await open(tester, backend);
    expect(find.text('Hello, Test Supervisor'), findsOneWidget);
    expect(find.text('Account connected'), findsNothing);
    expect(find.text('Supervisor workspace'), findsOneWidget);
    await nav(tester, 'Profile');
    await tap(tester, find.text('Sign Out'));
    expect(client.auth.currentSession, isNull);
    expect(find.text('Welcome to JANITRA'), findsOneWidget);
  });

  for (final agencyWide in [true, false]) {
    testWidgets(
      '${agencyWide ? 'agency-wide' : 'site-specific'} Supervisor sees a single manpower agency across workspace screens',
      (tester) async {
        final backend = WorkspaceTestBackend()..addSite();
        backend.roles.single['site_id'] = agencyWide ? null : fixtureSiteId;
        await open(tester, backend);
        final agency = find.byKey(const ValueKey('current-agency'));
        void expectAgency() {
          expect(agency, findsOneWidget);
          expect(
            find.descendant(of: agency, matching: find.text('Test Manpower')),
            findsOneWidget,
          );
          expect(find.byType(DropdownButtonFormField<String>), findsNothing);
        }

        expectAgency();
        await nav(tester, 'Workplaces');
        expectAgency();
        expect(
          find.byTooltip('Add Client Company'),
          agencyWide ? findsOneWidget : findsNothing,
        );
        await nav(tester, 'Profile');
        expectAgency();
        expect(
          find.byTooltip('Edit company Test Manpower'),
          agencyWide ? findsOneWidget : findsNothing,
        );
        expect(backend.writes, isEmpty);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('single agency label fits a narrow phone with large text', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    final backend = WorkspaceTestBackend()..addSite();
    const name = 'A long manpower agency name for the assigned Supervisor';
    backend.agencies.single['name'] = name;
    backend.roles.single['site_id'] = fixtureSiteId;
    await open(tester, backend);
    expect(find.byKey(const ValueKey('current-agency')), findsOneWidget);
    expect(find.byTooltip(name), findsOneWidget);
    expect(find.text(name), findsOneWidget);
    expect(tester.takeException(), isNull);
    await nav(tester, 'Workplaces');
    expect(find.byTooltip('Add Workplace'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  for (final agencyWide in [true, false]) {
    testWidgets(
      '${agencyWide ? 'company-wide' : 'site-specific'} Supervisor directory respects cross-company management scope',
      (tester) async {
        final backend = WorkspaceTestBackend()..addSite();
        backend.roles.single['site_id'] = agencyWide ? null : fixtureSiteId;
        backend.managedUsers.addAll([
          {
            'user_id': 'own-person',
            'full_name': 'Own Personnel',
            'role': 'personnel',
            'agency_id': fixtureAgencyId,
            'agency_name': 'Test Manpower',
            'site_id': fixtureSiteId,
            'is_active': true,
            'can_delete': true,
          },
          {
            'user_id': 'foreign-person',
            'full_name': 'Other Personnel',
            'role': 'personnel',
            'agency_id': 'other-agency',
            'agency_name': 'Other Agency',
            'site_id': 'other-site',
            'site_name': 'Other Workplace',
            'is_active': true,
            'can_delete': true,
          },
          {
            'user_id': 'foreign-supervisor',
            'full_name': 'Other Supervisor',
            'role': 'supervisor',
            'agency_id': 'other-agency',
            'agency_name': 'Other Agency',
            'site_id': null,
            'is_active': true,
            'can_delete': false,
          },
          {
            'user_id': 'admin',
            'full_name': 'Hidden Admin',
            'role': 'admin',
            'agency_id': null,
            'site_id': null,
            'is_active': true,
          },
        ]);
        await open(tester, backend);
        await tapFunction(tester, find.text('Team'));
        expect(find.text('Own Personnel'), findsOneWidget);
        expect(find.text('Hidden Admin'), findsNothing);
        expect(find.byType(DropdownButtonFormField<String>), findsNothing);
        if (agencyWide) {
          expect(find.text('All agency assignments'), findsOneWidget);
          expect(find.text('Other Personnel'), findsOneWidget);
          await tester.scrollUntilVisible(
            find.text('Other Supervisor'),
            150,
            scrollable: find.byType(Scrollable).last,
          );
          expect(find.text('Other Supervisor'), findsOneWidget);
          expect(find.byTooltip('Manage Other Personnel'), findsOneWidget);
          expect(find.byTooltip('Manage Other Supervisor'), findsNothing);
          await tester.scrollUntilVisible(
            find.byTooltip('Refresh people').hitTestable(),
            -200,
            scrollable: find.byType(Scrollable).last,
          );
          await tapFunction(tester, find.byTooltip('Refresh people'));
          expect(find.text('Other Personnel'), findsOneWidget);
          expect(find.byTooltip('Manage Own Personnel'), findsOneWidget);
          expect(find.text('Add'), findsOneWidget);
          await tap(tester, find.byTooltip('Manage Other Personnel'));
          expect(find.text('Edit Personnel'), findsOneWidget);
          expect(find.text('Manage PIN'), findsOneWidget);
          expect(find.text('Setup / recovery code'), findsOneWidget);
          expect(find.text('Delete account permanently'), findsOneWidget);
          await tapFunction(tester, find.text('Setup / recovery code'));
          expect(find.text('Issue account code'), findsOneWidget);
          await tap(tester, find.text('Cancel'));
          await tap(tester, find.byTooltip('Manage Other Personnel'));
          await tapFunction(tester, find.text('Suspend access'));
          await tester.enterText(find.byType(TextFormField), 'test-password');
          await tapFunction(tester, find.text('Suspend'));
          final change = backend.functionCalls.lastWhere(
            (call) => call['action'] == 'set_active',
          );
          expect(change['agency_id'], 'other-agency');
          expect(change['user_id'], 'foreign-person');
          expect(change['site_id'], 'other-site');
        } else {
          expect(find.text('All agency assignments'), findsNothing);
          expect(find.text('Other Personnel'), findsNothing);
          expect(find.text('Other Supervisor'), findsNothing);
        }
        expect(backend.writes, isEmpty);
        expect(
          backend.functionCalls.where(
            (call) =>
                call['action'] != 'list' && call['action'] != 'set_active',
          ),
          isEmpty,
        );
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'Supervisor sees scoped Supervisors without management actions and Admins stay hidden',
    (tester) async {
      final backend = WorkspaceTestBackend()..addSite();
      backend.managedUsers.addAll([
        {
          'user_id': 'other-supervisor',
          'full_name': 'Other Supervisor',
          'role': 'supervisor',
          'agency_id': fixtureAgencyId,
          'site_id': null,
          'is_active': true,
          'can_delete': false,
        },
        {
          'user_id': 'admin',
          'full_name': 'Hidden Admin',
          'role': 'admin',
          'agency_id': null,
          'site_id': null,
          'is_active': true,
          'can_delete': false,
        },
      ]);
      await open(tester, backend);
      await tapFunction(tester, find.text('Team'));
      expect(find.text('Other Supervisor'), findsOneWidget);
      expect(find.byTooltip('Manage Other Supervisor'), findsNothing);
      expect(find.text('Supervisor Management'), findsNothing);
      expect(find.text('Hidden Admin'), findsNothing);
    },
  );

  testWidgets(
    'metadata cannot grant access; refresh picks up authorized assignment',
    (tester) async {
      final backend = WorkspaceTestBackend()..roles = [];
      await open(tester, backend);
      expect(find.text('Workspace access pending'), findsOneWidget);
      expect(
        find.image(const AssetImage('assets/icons/janitra_launcher_1024.png')),
        findsOneWidget,
      );
      expect(find.byType(NavigationBar), findsNothing);
      backend.roles = [
        {'role': 'supervisor', 'agency_id': fixtureAgencyId, 'site_id': null},
      ];
      await tap(tester, find.text('Refresh access'));
      expect(find.text('Hello, Test Supervisor'), findsOneWidget);
    },
  );

  testWidgets(
    'failed authorization stays closed until retry; resumed suspension revokes UI',
    (tester) async {
      final backend = WorkspaceTestBackend()..failAccess = true;
      await open(tester, backend);
      expect(
        find.textContaining('Could not load your workplace access'),
        findsOneWidget,
      );
      expect(find.byType(NavigationBar), findsNothing);
      backend.failAccess = false;
      await tap(tester, find.text('Try again'));
      expect(find.byType(NavigationBar), findsOneWidget);
      backend.active = false;
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump(const Duration(milliseconds: 350));
      await tester.pumpAndSettle();
      expect(find.byType(NavigationBar), findsNothing);
      expect(find.text('Workspace access pending'), findsOneWidget);
    },
  );

  testWidgets('client and workplace creation validate, trim and send scope', (
    tester,
  ) async {
    final backend = WorkspaceTestBackend();
    await open(tester, backend);
    await nav(tester, 'Workplaces');
    expect(
      tester
          .widget<TextButton>(
            find.descendant(
              of: find.byTooltip('Add Workplace'),
              matching: find.byType(TextButton),
            ),
          )
          .onPressed,
      isNull,
    );
    await tap(tester, find.byTooltip('Add Client Company'));
    await tap(tester, find.widgetWithText(FilledButton, 'Add'));
    expect(find.text('Enter a name.'), findsOneWidget);
    expect(backend.writes, isEmpty);
    await tester.enterText(find.byType(TextFormField), '  New Client  ');
    await tap(tester, find.widgetWithText(FilledButton, 'Add'));
    expect(jsonDecode(backend.writes.single.body), {
      'agency_id': fixtureAgencyId,
      'name': 'New Client',
    });
    await tap(tester, find.byTooltip('Add Workplace'));
    await tester.enterText(find.byType(TextFormField), '  Main Office  ');
    await tap(tester, find.widgetWithText(FilledButton, 'Add'));
    expect(jsonDecode(backend.writes.last.body), {
      'agency_id': fixtureAgencyId,
      'client_company_id': backend.clients.single['id'],
      'name': 'Main Office',
    });
    expect(find.text('Main Office'), findsOneWidget);
  });

  testWidgets('Audit log groups events, filters them, and shows safe details', (
    tester,
  ) async {
    final backend = WorkspaceTestBackend()..addSite();
    backend.workTables['audit_events'] = [
      {
        'id': 'event-1',
        'agency_id': fixtureAgencyId,
        'entity_type': 'sites',
        'action': 'update',
        'occurred_at': '2026-10-18T08:30:00Z',
        'before_data': {'name': 'Old Office', 'password': 'secret-test'},
        'after_data': {'name': 'New Office', 'password': 'new-secret'},
      },
      {
        'id': 'event-2',
        'agency_id': fixtureAgencyId,
        'entity_type': 'client_companies',
        'action': 'insert',
        'occurred_at': '2026-10-17T08:30:00Z',
        'before_data': {},
        'after_data': {'name': 'Client A'},
      },
    ];
    await open(tester, backend);
    await nav(tester, 'Workplaces');
    await tap(tester, find.text('Audit log'));
    expect(find.text('2 recorded events'), findsOneWidget);
    expect(find.text('Workplace Updated'), findsOneWidget);
    expect(find.text('Client company Added'), findsOneWidget);
    final dateLabel = MaterialLocalizations.of(
      tester.element(find.text('Workplace Updated')),
    ).formatMediumDate(DateTime(2026, 10, 18));
    expect(find.text(dateLabel), findsOneWidget);
    await tap(tester, find.text('Updated'));
    expect(find.text('Workplace Updated'), findsOneWidget);
    expect(find.text('Client company Added'), findsNothing);
    await tap(tester, find.text('Workplace Updated'));
    expect(find.text('Event details'), findsOneWidget);
    expect(find.text('BEFORE'), findsOneWidget);
    expect(find.text('Old Office'), findsOneWidget);
    expect(find.text('New Office'), findsOneWidget);
    expect(find.textContaining('secret-test'), findsNothing);
    await tap(tester, find.widgetWithText(FilledButton, 'Close'));
    await tap(tester, find.text('Added'));
    expect(find.text('Client company Added'), findsOneWidget);
    expect(find.text('Workplace Updated'), findsNothing);
  });

  testWidgets('rejected writes stay editable and loading prevents duplicates', (
    tester,
  ) async {
    final backend = WorkspaceTestBackend()..rejectWrites = true;
    await open(tester, backend);
    await nav(tester, 'Workplaces');
    await tap(tester, find.byTooltip('Add Client Company'));
    await tester.enterText(find.byType(TextFormField), 'Test Client');
    await tap(tester, find.widgetWithText(FilledButton, 'Add'));
    expect(find.textContaining('This name already exists'), findsOneWidget);
    expect(backend.clients, isEmpty);
    backend.rejectWrites = false;
    backend.pendingWrite = Completer<void>();
    await tester.tap(find.widgetWithText(FilledButton, 'Add'));
    await tester.pump();
    expect(
      tester.widget<FilledButton>(find.byType(FilledButton).last).onPressed,
      isNull,
    );
    expect(
      tester
          .widget<OutlinedButton>(find.widgetWithText(OutlinedButton, 'Cancel'))
          .onPressed,
      isNull,
    );
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();
    await tester.dragFrom(
      tester.getTopLeft(find.byType(BottomSheet)) + const Offset(30, 15),
      const Offset(0, 700),
    );
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.byType(NameEditor), findsOneWidget);
    expect(backend.writes.length, 2);
    backend.pendingWrite!.complete();
    await tester.pumpAndSettle();
    expect(find.byType(NameEditor), findsNothing);
    expect(backend.clients.length, 1);
  });

  testWidgets(
    'renames send only permitted columns and own profile identifier',
    (tester) async {
      final backend = WorkspaceTestBackend()..addSite();
      await open(tester, backend);
      await nav(tester, 'Workplaces');
      await tap(tester, find.byTooltip('Edit client Test Client'));
      await tester.enterText(find.byType(TextFormField), 'Renamed Client');
      await tap(tester, find.text('Save changes'));
      expect(jsonDecode(backend.writes.last.body), {'name': 'Renamed Client'});
      await tap(tester, find.byTooltip('Edit workplace Test Workplace'));
      expect(find.text('Client company: Renamed Client'), findsOneWidget);
      await tester.enterText(find.byType(TextFormField), 'Renamed Workplace');
      await tap(tester, find.text('Save changes'));
      expect(jsonDecode(backend.writes.last.body), {
        'name': 'Renamed Workplace',
      });
      await nav(tester, 'Profile');
      await tap(tester, find.text('Edit Your Name'));
      await tester.enterText(find.byType(TextFormField), 'Renamed Supervisor');
      await tap(tester, find.text('Save changes'));
      expect(jsonDecode(backend.writes.last.body), {
        'full_name': 'Renamed Supervisor',
      });
      expect(
        backend.writes.last.url.queryParameters['id'],
        'eq.$fixtureUserId',
      );
      await tap(tester, find.byTooltip('Edit company Test Manpower'));
      await tester.enterText(find.byType(TextFormField), 'Renamed Agency');
      await tap(tester, find.text('Save changes'));
      expect(jsonDecode(backend.writes.last.body), {'name': 'Renamed Agency'});
      expect(
        backend.writes.last.url.queryParameters['id'],
        'eq.$fixtureAgencyId',
      );
    },
  );

  testWidgets('Personnel has assigned workplaces and no management controls', (
    tester,
  ) async {
    final backend = WorkspaceTestBackend()
      ..addSite()
      ..roles = [
        {
          'role': 'personnel',
          'agency_id': fixtureAgencyId,
          'site_id': fixtureSiteId,
        },
      ];
    await open(tester, backend);
    expect(find.text('Hello, Test Supervisor'), findsOneWidget);
    expect(find.text('Test Workplace'), findsOneWidget);
    expect(find.text('Workplaces'), findsNothing);
    expect(find.byTooltip('Edit workplace Test Workplace'), findsNothing);
    await nav(tester, 'Profile');
    expect(find.byTooltip('Edit company Test Manpower'), findsNothing);
  });

  testWidgets('invited Personnel must set a password before opening work', (
    tester,
  ) async {
    final backend = WorkspaceTestBackend()
      ..addSite()
      ..passwordNeeded = true
      ..roles = [
        {
          'role': 'personnel',
          'agency_id': fixtureAgencyId,
          'site_id': fixtureSiteId,
        },
      ];
    await open(tester, backend);
    expect(find.text('Set Your Password'), findsOneWidget);
    expect(find.text('Personnel workspace'), findsNothing);
    await tester.enterText(
      find.byType(TextFormField).at(0),
      'new-test-password',
    );
    await tester.enterText(
      find.byType(TextFormField).at(1),
      'new-test-password',
    );
    await tap(tester, find.text('Save Password'));
    expect(find.text('Test Workplace'), findsOneWidget);
    expect(backend.passwordNeeded, isFalse);
    expect(
      backend.requests.where(
        (request) =>
            request.url.path.endsWith('/user') && request.method == 'PUT',
      ),
      hasLength(1),
    );
  });

  testWidgets('Team status stays at the right edge of each person card', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(400, 850);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final backend = WorkspaceTestBackend()..addSite();
    backend.managedUsers.addAll([
      {
        'user_id': '00000000-0000-0000-0000-000000000003',
        'full_name': 'Active Cleaner',
        'username': 'cleaner123',
        'role': 'personnel',
        'site_id': fixtureSiteId,
        'is_active': true,
      },
      {
        'user_id': '00000000-0000-0000-0000-000000000004',
        'full_name': 'Inactive Cleaner',
        'email': 'inactive@example.test',
        'role': 'personnel',
        'site_id': fixtureSiteId,
        'is_active': false,
      },
    ]);
    await open(tester, backend);
    await nav(tester, 'Workplaces');
    await tapFunction(tester, find.text('People'));

    for (final (name, status) in [
      ('Active Cleaner', 'Active'),
      ('Inactive Cleaner', 'Suspended'),
    ]) {
      final card = find
          .ancestor(of: find.text(name), matching: find.byType(Card))
          .first;
      final badge = find.descendant(of: card, matching: find.text(status));
      expect(badge, findsOneWidget);
      final distanceFromRight =
          tester.getRect(card).right - tester.getRect(badge).right;
      expect(distanceFromRight, lessThan(44));
    }
  });

  testWidgets('agency Supervisor invites and suspends workplace Personnel', (
    tester,
  ) async {
    final backend = WorkspaceTestBackend()..addSite();
    await open(tester, backend);
    await nav(tester, 'Workplaces');
    await tapFunction(tester, find.text('People'));
    expect(find.text('No team members yet.'), findsOneWidget);
    await tap(tester, find.text('Add person'));
    await tap(tester, find.text('Username and password'));
    await tap(tester, find.text('Email invitation').last);
    await tap(tester, find.text('Send invite'));
    expect(find.text('Enter a name.'), findsOneWidget);
    expect(
      backend.functionCalls.where((call) => call['action'] == 'invite'),
      isEmpty,
    );
    await tester.enterText(find.byType(TextFormField).at(0), '  New Worker  ');
    await tester.enterText(
      find.byType(TextFormField).at(1),
      '  new.worker@example.test  ',
    );
    await tester.enterText(find.byType(TextFormField).at(2), 'test-password');
    await tapFunction(tester, find.text('Send invite'));
    expect(
      backend.functionCalls.firstWhere((call) => call['action'] == 'invite'),
      {
        'action': 'invite',
        'agency_id': fixtureAgencyId,
        'role': 'personnel',
        'site_id': fixtureSiteId,
        'full_name': 'New Worker',
        'email': 'new.worker@example.test',
        'password': 'test-password',
      },
    );
    expect(find.text('New Worker'), findsOneWidget);
    await tap(tester, find.byTooltip('Manage New Worker'));
    await tap(tester, find.text('Suspend access'));
    await tap(tester, find.text('Suspend').last);
    expect(find.text('Enter confirm your account password.'), findsOneWidget);
    await tester.enterText(find.byType(TextField).last, 'test-password');
    await tapFunction(tester, find.text('Suspend').last);
    expect(backend.managedUsers.single['is_active'], isFalse);
    expect(find.text('Suspended'), findsOneWidget);
    await tap(tester, find.byTooltip('Manage New Worker'));
    await tap(tester, find.text('Reactivate access'));
    await tester.enterText(find.byType(TextField).last, 'test-password');
    await tapFunction(tester, find.text('Reactivate').last);
    expect(backend.managedUsers.single['is_active'], isTrue);
    await tap(tester, find.text('Add person'));
    expect(find.text('Supervisor'), findsNothing);
    expect(find.text('Supervisor Management'), findsNothing);
    await tap(tester, find.text('Cancel'));
  });

  testWidgets(
    'Employee PIN keypad checks matching, clears rejected credentials, and preserves scope',
    (tester) async {
      final backend = WorkspaceTestBackend()
        ..addSite()
        ..rejectPinWrites = true;
      backend.managedUsers.add({
        'user_id': '00000000-0000-0000-0000-000000000003',
        'full_name': 'Worker',
        'email': 'worker@example.test',
        'role': 'personnel',
        'site_id': fixtureSiteId,
        'is_active': true,
      });
      await open(tester, backend);
      await nav(tester, 'Workplaces');
      await tapFunction(tester, find.text('People'));
      await tap(tester, find.byTooltip('Manage Worker'));
      await tapFunction(tester, find.text('Manage PIN'));
      expect(find.text('No PIN configured'), findsOneWidget);
      await tap(tester, find.text('Set PIN'));
      expect(find.text('Set Employee PIN'), findsOneWidget);
      expect(find.text('For Worker'), findsOneWidget);
      expect(find.byKey(const ValueKey('employee-pin-keypad')), findsOneWidget);
      expect(find.byType(TextFormField), findsNothing);
      expect(backend.pinStates, isEmpty);
      expect(
        tester
            .widget<FilledButton>(find.widgetWithText(FilledButton, 'Continue'))
            .onPressed,
        isNull,
      );
      for (final digit in ['0', '0', '4', '2']) {
        await tap(tester, find.widgetWithText(OutlinedButton, digit));
      }
      expect(
        find.bySemanticsLabel('4 of 4 PIN digits entered'),
        findsOneWidget,
      );
      await tap(tester, find.text('Continue'));
      expect(find.text('Repeat your PIN'), findsOneWidget);
      for (final digit in ['0', '0', '4', '3']) {
        await tap(tester, find.widgetWithText(OutlinedButton, digit));
      }
      await tap(tester, find.text('Continue'));
      expect(find.text('PINs do not match. Try again.'), findsOneWidget);
      expect(find.text('Confirm your identity'), findsNothing);
      expect(
        backend.functionCalls.where((call) => call['action'] == 'set'),
        isEmpty,
      );
      for (final digit in ['0', '0', '4', '2']) {
        await tap(tester, find.widgetWithText(OutlinedButton, digit));
      }
      await tap(tester, find.text('Continue'));
      expect(find.text('Confirm your identity'), findsOneWidget);
      expect(
        find.text('Enter your Supervisor account password to save.'),
        findsOneWidget,
      );
      await tester.enterText(
        find.byKey(const ValueKey('employee-pin-password')),
        'test-password',
      );
      await tapFunction(tester, find.text('Save PIN'));
      expect(find.text('Password confirmation failed.'), findsOneWidget);
      expect(find.text('Choose a new PIN'), findsOneWidget);
      expect(
        find.bySemanticsLabel('0 of 4 PIN digits entered'),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('employee-pin-password')), findsNothing);

      backend.rejectPinWrites = false;
      for (final digit in ['0', '0', '4', '2']) {
        await tap(tester, find.widgetWithText(OutlinedButton, digit));
      }
      await tap(tester, find.text('Continue'));
      for (final digit in ['0', '0', '4', '2']) {
        await tap(tester, find.widgetWithText(OutlinedButton, digit));
      }
      await tap(tester, find.text('Continue'));
      await tester.enterText(
        find.byKey(const ValueKey('employee-pin-password')),
        'test-password',
      );
      await tapFunction(tester, find.text('Save PIN'));
      expect(find.text('PIN configured'), findsOneWidget);
      expect(find.text('0042'), findsNothing);
      final write = backend.functionCalls.lastWhere(
        (call) => call['action'] == 'set',
      );
      expect(write['kind'], 'employee');
      expect(write['pin'], '0042');
      expect(write['site_id'], fixtureSiteId);
      expect(write['user_id'], '00000000-0000-0000-0000-000000000003');
      await tap(tester, find.text('Reset PIN'));
      expect(find.text('Reset Employee PIN'), findsOneWidget);
      expect(
        find.textContaining('employee’s previous PIN stops working'),
        findsOneWidget,
      );
      await tap(tester, find.text('Cancel'));
      expect(find.text('Reset Employee PIN'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'Employee PIN keypad clears secrets when app backgrounds at small size',
    (tester) async {
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1;
      tester.platformDispatcher.textScaleFactorTestValue = 2;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      final backend = WorkspaceTestBackend()..addSite();
      backend.managedUsers.add({
        'user_id': '00000000-0000-0000-0000-000000000003',
        'full_name': 'Worker',
        'email': 'worker@example.test',
        'role': 'personnel',
        'site_id': fixtureSiteId,
        'is_active': true,
      });
      await open(tester, backend);
      await nav(tester, 'Workplaces');
      await tapFunction(tester, find.text('People'));
      final manageWorker = find.widgetWithIcon(IconButton, Icons.more_vert);
      await tester.scrollUntilVisible(
        manageWorker.hitTestable(),
        150,
        scrollable: find.byType(Scrollable).last,
      );
      await tester.tap(manageWorker.hitTestable());
      await tester.pumpAndSettle();
      await tapFunction(tester, find.text('Manage PIN'));
      await tap(tester, find.text('Set PIN'));
      for (final digit in ['0', '0', '4']) {
        await tap(tester, find.widgetWithText(OutlinedButton, digit));
      }
      expect(
        find.bySemanticsLabel('3 of 4 PIN digits entered'),
        findsOneWidget,
      );
      await tap(tester, find.byIcon(Icons.backspace_outlined));
      expect(
        find.bySemanticsLabel('2 of 4 PIN digits entered'),
        findsOneWidget,
      );
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      await tester.pump();
      expect(find.text('Choose a new PIN'), findsOneWidget);
      expect(
        find.bySemanticsLabel('0 of 4 PIN digits entered'),
        findsOneWidget,
      );
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();
      await tap(tester, find.byTooltip('Close PIN setup'));
      expect(
        backend.functionCalls.where((call) => call['action'] == 'set'),
        isEmpty,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('Supervisor PIN setup uses keypad and password, at 320px/200%', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    final backend = WorkspaceTestBackend()..addSite();
    await open(tester, backend);
    await nav(tester, 'Profile');
    await tapFunction(tester, find.text('Manage Your Supervisor PIN'));
    expect(find.text('Supervisor PIN'), findsOneWidget);
    await tap(tester, find.text('Set PIN'));
    expect(find.text('Choose a new PIN'), findsOneWidget);
    expect(find.byType(TextFormField), findsNothing);
    for (final digit in ['0', '0', '1', '2']) {
      final key = find.widgetWithText(OutlinedButton, digit);
      await tester.ensureVisible(key);
      await tester.tap(key);
      await tester.pump();
    }
    expect(find.bySemanticsLabel('4 of 4 PIN digits entered'), findsOneWidget);
    await tap(tester, find.text('Continue'));
    expect(find.text('Repeat your PIN'), findsOneWidget);
    for (final digit in ['0', '0', '1', '2']) {
      final key = find.widgetWithText(OutlinedButton, digit);
      await tester.ensureVisible(key);
      await tester.tap(key);
      await tester.pump();
    }
    await tap(tester, find.text('Continue'));
    expect(find.text('Confirm your identity'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('supervisor-pin-password')),
      findsOneWidget,
    );
    expect(
      backend.functionCalls.where((call) => call['action'] == 'set'),
      isEmpty,
    );
    await tester.enterText(
      find.byKey(const ValueKey('supervisor-pin-password')),
      'test-password',
    );
    await tapFunction(tester, find.text('Save PIN'));
    expect(find.text('PIN configured'), findsOneWidget);
    final write = backend.functionCalls.lastWhere(
      (call) => call['action'] == 'set',
    );
    expect(write['kind'], 'supervisor');
    expect(write['user_id'], fixtureUserId);
    expect(write['site_id'], isNull);
    expect(write['pin'], '0012');
    expect(find.text('0012'), findsNothing);
    expect(tester.takeException(), isNull);
    await tap(tester, find.text('Reset PIN'));
    expect(find.text('Update Supervisor PIN'), findsOneWidget);
    expect(find.textContaining('previous PIN stops working'), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.text('Update Supervisor PIN'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'Supervisor PIN setup rejects mismatches and clears on background',
    (tester) async {
      final backend = WorkspaceTestBackend()..addSite();
      await open(tester, backend);
      await nav(tester, 'Profile');
      await tapFunction(tester, find.text('Manage Your Supervisor PIN'));
      await tap(tester, find.text('Set PIN'));
      for (final digit in ['0', '0', '4', '2']) {
        await tap(tester, find.widgetWithText(OutlinedButton, digit));
      }
      await tap(tester, find.text('Continue'));
      for (final digit in ['0', '0', '4', '3']) {
        await tap(tester, find.widgetWithText(OutlinedButton, digit));
      }
      await tap(tester, find.text('Continue'));
      expect(find.text('PINs do not match. Try again.'), findsOneWidget);
      expect(find.text('Confirm your identity'), findsNothing);
      expect(
        backend.functionCalls.where((call) => call['action'] == 'set'),
        isEmpty,
      );
      await tap(tester, find.widgetWithText(OutlinedButton, '4'));
      expect(
        find.bySemanticsLabel('1 of 4 PIN digits entered'),
        findsOneWidget,
      );
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      await tester.pump();
      expect(find.text('Choose a new PIN'), findsOneWidget);
      expect(
        find.bySemanticsLabel('0 of 4 PIN digits entered'),
        findsOneWidget,
      );
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();
      await tap(tester, find.byTooltip('Close PIN setup'));
      expect(
        backend.functionCalls.where((call) => call['action'] == 'set'),
        isEmpty,
      );
    },
  );

  testWidgets(
    'PIN metadata cannot enable a reset outside the managers full scope',
    (tester) async {
      final backend = WorkspaceTestBackend()
        ..addSite()
        ..allowPinReset = false;
      backend.managedUsers.add({
        'user_id': '00000000-0000-0000-0000-000000000003',
        'full_name': 'Worker',
        'email': 'worker@example.test',
        'role': 'personnel',
        'site_id': fixtureSiteId,
        'is_active': true,
      });
      await open(tester, backend);
      await nav(tester, 'Workplaces');
      await tapFunction(tester, find.text('People'));
      await tap(tester, find.byTooltip('Manage Worker'));
      await tapFunction(tester, find.text('Manage PIN'));
      expect(
        find.textContaining('assignments outside your scope'),
        findsOneWidget,
      );
      expect(find.text('Set PIN'), findsNothing);
      expect(find.text('Reset PIN'), findsNothing);
    },
  );

  testWidgets('site Supervisor invites only to the assigned workplace', (
    tester,
  ) async {
    final backend = WorkspaceTestBackend()
      ..addSite()
      ..roles = [
        {
          'role': 'supervisor',
          'agency_id': fixtureAgencyId,
          'site_id': fixtureSiteId,
        },
      ];
    await open(tester, backend);
    await nav(tester, 'Workplaces');
    await tapFunction(tester, find.text('People'));
    await tap(tester, find.text('Add person'));
    expect(find.text('Role'), findsNothing);
    expect(find.text('Test Workplace'), findsWidgets);
    await tap(tester, find.text('Username and password'));
    await tap(tester, find.text('Email invitation').last);
    await tester.enterText(find.byType(TextFormField).at(0), 'Worker');
    await tester.enterText(
      find.byType(TextFormField).at(1),
      'worker@example.test',
    );
    await tester.enterText(find.byType(TextFormField).at(2), 'test-password');
    await tapFunction(tester, find.text('Send invite'));
    final invite = backend.functionCalls.firstWhere(
      (call) => call['action'] == 'invite',
    );
    expect(invite['role'], 'personnel');
    expect(invite['site_id'], fixtureSiteId);
  });

  testWidgets(
    'site Supervisor may rename own site but cannot create agency records',
    (tester) async {
      final backend = WorkspaceTestBackend()
        ..addSite()
        ..roles = [
          {
            'role': 'supervisor',
            'agency_id': fixtureAgencyId,
            'site_id': fixtureSiteId,
          },
        ];
      await open(tester, backend);
      await nav(tester, 'Workplaces');
      expect(find.byTooltip('Add Client Company'), findsNothing);
      expect(find.byTooltip('Add Workplace'), findsNothing);
      expect(find.byTooltip('Edit client Test Client'), findsNothing);
      await tap(tester, find.byTooltip('Edit workplace Test Workplace'));
      await tester.enterText(find.byType(TextFormField), 'Edited Site');
      await tap(tester, find.text('Save changes'));
      expect(backend.sites.single['name'], 'Edited Site');
    },
  );

  testWidgets('mixed roles do not grant management in Personnel agency', (
    tester,
  ) async {
    final backend = WorkspaceTestBackend()..addSite();
    const other = '10000000-0000-0000-0000-000000000002';
    backend.agencies.add({'id': other, 'name': 'Other Manpower'});
    backend.roles = [
      {...backend.roles.single, 'site_id': fixtureSiteId},
      {'role': 'personnel', 'agency_id': other, 'site_id': 'other-site'},
    ];
    await open(tester, backend);
    await tester.tap(find.byType(DropdownButtonFormField<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Other Manpower').last);
    await tester.pumpAndSettle();
    expect(find.text('Your workplaces'), findsNothing);
    await nav(tester, 'Workplaces');
    expect(find.byTooltip('Add Client Company'), findsNothing);
    expect(find.byTooltip('Add Workplace'), findsNothing);
  });

  testWidgets('narrow phone at 200 percent keeps forms and navigation usable', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    final backend = WorkspaceTestBackend()..addSite();
    await open(tester, backend);
    expect(tester.takeException(), isNull);
    await nav(tester, 'Workplaces');
    await tap(tester, find.byTooltip('Add Workplace'));
    await tap(tester, find.widgetWithText(FilledButton, 'Add'));
    expect(find.text('Enter a name.'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tap(tester, find.text('Cancel'));
    expect(find.byType(NameEditor), findsNothing);
  });

  testWidgets('People and invite form remain usable at 320px and 200 percent', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    final backend = WorkspaceTestBackend()..addSite();
    await open(tester, backend);
    await nav(tester, 'Workplaces');
    await tapFunction(tester, find.text('People'));
    expect(tester.takeException(), isNull);
    await tap(tester, find.text('Add person'));
    expect(tester.takeException(), isNull);
    await tap(tester, find.text('Create account'));
    expect(find.text('Enter a name.'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tap(tester, find.text('Cancel'));
    expect(find.byType(AlertDialog), findsNothing);
    await tap(tester, find.text('Add person'));
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
  });

  test(
    'paginated responses do not silently truncate workplace counts',
    () async {
      final backend = WorkspaceTestBackend();
      for (var i = 0; i < 205; i++) {
        backend.clients.add({
          'id': 'client-$i',
          'agency_id': fixtureAgencyId,
          'name': 'Client $i',
        });
      }
      final client = SupabaseClient(
        'https://example.supabase.co',
        'sb_publishable_test',
        httpClient: MockClient(backend.handle),
        authOptions: const AuthClientOptions(autoRefreshToken: false),
      );
      try {
        final rows = await readWorkspaceRows(
          client
              .from('client_companies')
              .select('id,agency_id,name')
              .eq('agency_id', fixtureAgencyId),
        );
        expect(rows.length, 205);
        expect(
          backend.requests
              .where((r) => r.url.path.endsWith('/client_companies'))
              .length,
          2,
        );
      } finally {
        await client.dispose();
      }
    },
  );
}
