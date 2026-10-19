import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:janitra/features/authentication/login_page.dart';
import 'package:janitra/features/authentication/account_setup_page.dart';
import 'package:janitra/features/workspace/account_code_page.dart';
import 'package:janitra/features/workspace/people_page.dart';
import 'package:janitra/features/workspace/workspace_access.dart';
import 'package:janitra/features/work/scheduling_page.dart';
import 'package:janitra/features/workspace/supervisor_access_sheet.dart';
import 'package:janitra/core/app_theme.dart';
import 'package:janitra/features/reports/reports_page.dart';
import 'package:janitra/features/work/work_form.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'fixtures/workspace_backend.dart';

void main() {
  Future<SupabaseClient> clientFor(
    WidgetTester tester,
    Future<http.Response> Function(http.Request) handle,
  ) async {
    final client = (await tester.runAsync(
      () async => SupabaseClient(
        'https://example.supabase.co',
        'test',
        httpClient: MockClient(handle),
        authOptions: const AuthClientOptions(autoRefreshToken: false),
      ),
    ))!;
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox());
      await tester.runAsync(client.dispose);
    });
    return client;
  }

  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 4; i++) {
      await tester.pump();
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 40)),
      );
    }
    await tester.pumpAndSettle();
  }

  testWidgets(
    'Admin Supervisor editor preserves cancel and clears passwords on background',
    (tester) async {
      final backend = WorkspaceTestBackend()..addSite();
      final supervisor = <String, dynamic>{
        'user_id': '00000000-0000-0000-0000-000000000002',
        'role': 'supervisor',
        'agency_id': fixtureAgencyId,
        'site_id': null,
        'full_name': 'Managed Supervisor',
        'is_active': true,
        'account_active': true,
        'can_delete': true,
      };
      Map<String, dynamic>? changed;
      var lists = 0;
      final client = await clientFor(tester, (request) async {
        if (request.url.path.endsWith('/manage-users')) {
          final body = jsonDecode(request.body) as Map<String, dynamic>;
          if (body['action'] == 'manage_supervisor') {
            changed = body;
            return http.Response(
              '{"updated":true}',
              200,
              headers: {'content-type': 'application/json'},
            );
          }
          lists++;
          return http.Response(
            jsonEncode({
              'users': [supervisor],
            }),
            200,
            headers: {'content-type': 'application/json'},
          );
        }
        return backend.handle(request);
      });
      await tester.runAsync(
        () => client.auth.signInWithPassword(
          email: 'admin@example.test',
          password: 'test-only',
        ),
      );
      await tester.pumpWidget(
        MaterialApp(
          home: PeoplePage(
            client: client,
            access: const WorkspaceAccess(
              fullName: 'Admin',
              roles: [
                {'role': 'admin', 'agency_id': null, 'site_id': null},
              ],
            ),
            agencyId: fixtureAgencyId,
            agencyName: 'Agency',
            sites: backend.sites,
          ),
        ),
      );
      await settle(tester);
      Future<void> edit() async {
        await tester.tap(find.byTooltip('Manage Managed Supervisor'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Edit Supervisor access'));
        await settle(tester);
      }

      await edit();
      await tester.ensureVisible(find.text('Cancel'));
      await tester.tap(find.text('Cancel'));
      await settle(tester);
      expect(lists, 1);
      expect(changed, isNull);
      await edit();
      await tester.tap(find.text('Company-Wide'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Site-Specific').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Test Workplace'));
      await tester.enterText(find.byType(TextFormField).last, 'secret-test');
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.ensureVisible(find.text('Save access'));
      await tester.tap(find.text('Save access'));
      await tester.pumpAndSettle();
      expect(find.text('Enter your password.'), findsOneWidget);
      expect(changed, isNull);
      await tester.enterText(find.byType(TextFormField).last, 'secret-test');
      await tester.ensureVisible(find.text('Save access'));
      await tester.tap(find.text('Save access'));
      await settle(tester);
      expect(changed?['site_ids'], [fixtureSiteId]);
      expect(changed?['user_id'], supervisor['user_id']);
      expect(changed?['is_active'], true);
      expect(lists, 2);
      expect(tester.takeException(), isNull);
    },
  );

  for (final role in ['supervisor', 'personnel']) {
    testWidgets(
      'Admin confirms permanent deletion of $role while retaining history',
      (tester) async {
        final backend = WorkspaceTestBackend()..addSite();
        backend.roles = [
          {'role': 'admin', 'agency_id': null, 'site_id': null},
        ];
        final people = <Map<String, dynamic>>[
          {
            'user_id': '00000000-0000-0000-0000-000000000002',
            'full_name': 'Test Account',
            'email': 'test@example.test',
            'role': role,
            'site_id': role == 'personnel' ? fixtureSiteId : null,
            'is_active': true,
            'can_delete': true,
            'agency_name': 'Other Agency',
          },
        ];
        Map<String, dynamic>? deleted;
        final client = await clientFor(tester, (request) async {
          if (request.url.path.endsWith('/manage-users')) {
            final body = jsonDecode(request.body) as Map<String, dynamic>;
            if (body['action'] == 'delete_account') {
              deleted = body;
              people.clear();
              return http.Response(
                '{"deleted":true}',
                200,
                headers: {'content-type': 'application/json'},
              );
            }
            return http.Response(
              jsonEncode({'users': people, 'permissions_version': 2}),
              200,
              headers: {'content-type': 'application/json'},
            );
          }
          return backend.handle(request);
        });
        await tester.runAsync(
          () => client.auth.signInWithPassword(
            email: 'owner@example.test',
            password: 'test-only',
          ),
        );
        await tester.pumpWidget(
          MaterialApp(
            home: PeoplePage(
              client: client,
              access: WorkspaceAccess(
                fullName: backend.fullName,
                roles: backend.roles,
              ),
              agencyId: fixtureAgencyId,
              agencyName: 'Agency',
              sites: backend.sites,
            ),
          ),
        );
        await settle(tester);
        expect(find.text('All agency assignments'), findsOneWidget);
        expect(find.text('1 active · 1 assignments'), findsOneWidget);
        expect(find.textContaining('Other Agency ·'), findsOneWidget);
        await tester.tap(find.byTooltip('Manage Test Account'));
        await tester.pumpAndSettle();
        await tester.ensureVisible(find.text('Delete account permanently'));
        await tester.tap(find.text('Delete account permanently'));
        await tester.pumpAndSettle();
        expect(find.textContaining('This cannot be undone.'), findsOneWidget);
        await tester.enterText(find.byType(TextFormField).at(0), 'delete');
        await tester.enterText(
          find.byType(TextFormField).at(1),
          'Owner-password',
        );
        await tester.tap(find.text('Delete account permanently'));
        await settle(tester);
        expect(deleted, isNull);
        await tester.enterText(find.byType(TextFormField).at(0), 'DELETE');
        await tester.tap(find.text('Delete account permanently'));
        await settle(tester);
        expect(deleted?['user_id'], '00000000-0000-0000-0000-000000000002');
        expect(deleted?['confirmation'], 'DELETE');
        expect(deleted?['password'], 'Owner-password');
        expect(find.text('Test Account'), findsNothing);
        expect(
          find.text('Account deleted. Historical records retained.'),
          findsOneWidget,
        );
      },
    );
  }

  testWidgets(
    'legacy backend cannot expose history-erasing deletion controls',
    (tester) async {
      final backend = WorkspaceTestBackend()..addSite();
      backend.managedUsers.add({
        'user_id': '00000000-0000-0000-0000-000000000002',
        'full_name': 'Test Personnel',
        'email': 'person@example.test',
        'role': 'personnel',
        'site_id': fixtureSiteId,
        'is_active': true,
        'can_delete': true,
      });
      final client = await clientFor(tester, (request) async {
        if (request.url.path.endsWith('/manage-users')) {
          return http.Response(
            jsonEncode({'users': backend.managedUsers}),
            200,
            headers: {'content-type': 'application/json'},
          );
        }
        return backend.handle(request);
      });
      await tester.runAsync(
        () => client.auth.signInWithPassword(
          email: 'manager@example.test',
          password: 'test-only',
        ),
      );
      await tester.pumpWidget(
        MaterialApp(
          home: PeoplePage(
            client: client,
            access: WorkspaceAccess(
              fullName: backend.fullName,
              roles: backend.roles,
            ),
            agencyId: fixtureAgencyId,
            agencyName: 'Agency',
            sites: backend.sites,
          ),
        ),
      );
      await settle(tester);
      await tester.tap(find.byTooltip('Manage Test Personnel'));
      await tester.pumpAndSettle();
      expect(find.text('Delete account permanently'), findsNothing);
      expect(find.text('Suspend access'), findsOneWidget);
    },
  );

  testWidgets('Supervisor access editor works at 320px and 200 percent text', (
    tester,
  ) async {
    await (FontLoader('Roboto')
          ..addFont(rootBundle.load('assets/fonts/Roboto-Regular.ttf'))
          ..addFont(rootBundle.load('assets/fonts/Roboto-Bold.ttf')))
        .load();
    await (FontLoader(
      'MaterialIcons',
    )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
    tester.view.physicalSize = const Size(320, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final client = await clientFor(
      tester,
      (_) async => http.Response('{}', 400),
    );
    await tester.pumpWidget(
      MaterialApp(
        theme: janitraTheme(),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: const TextScaler.linear(2)),
          child: child!,
        ),
        home: Scaffold(
          body: SupervisorAccessSheet(
            client: client,
            user: const {
              'full_name': 'A Supervisor',
              'agency_id': fixtureAgencyId,
              'is_active': true,
            },
            assignments: const [
              {
                'agency_id': fixtureAgencyId,
                'site_id': null,
                'is_active': true,
              },
            ],
            agencies: const [
              {'id': fixtureAgencyId, 'name': 'A manpower agency'},
            ],
            sites: const [
              {
                'id': fixtureSiteId,
                'agency_id': fixtureAgencyId,
                'name': 'A workplace',
              },
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Company-Wide'));
    await tester.tap(find.text('Company-Wide'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Site-Specific').last);
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('A workplace'));
    await tester.tap(find.text('A workplace'));
    await tester.ensureVisible(find.text('Save access'));
    await tester.tap(find.text('Save access'));
    await tester.pumpAndSettle();
    expect(find.text('Enter your password.'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await expectLater(
      find.byType(Scaffold),
      matchesGoldenFile('goldens/admin-access-large-text.png'),
    );
  });

  testWidgets(
    'report filters retain scoped Supervisors and exclude other agencies',
    (tester) async {
      final backend = WorkspaceTestBackend()..addSite();
      backend.managedUsers.addAll([
        {
          'user_id': 'manager',
          'full_name': 'Scoped Supervisor',
          'role': 'supervisor',
          'agency_id': fixtureAgencyId,
        },
        {
          'user_id': 'outside',
          'full_name': 'Other Supervisor',
          'role': 'supervisor',
          'agency_id': 'other-agency',
        },
      ]);
      final client = await clientFor(tester, backend.handle);
      await tester.pumpWidget(
        MaterialApp(
          home: ReportsPage(
            client: client,
            agencyId: fixtureAgencyId,
            agencyName: 'Agency',
            sites: backend.sites,
          ),
        ),
      );
      await settle(tester);
      await tester.tap(find.text('Weekly Report'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('PDF Work Report'));
      await tester.pumpAndSettle();
      final form = tester.widget<WorkForm>(find.byType(WorkForm));
      expect(
        form.fields.firstWhere((f) => f.keyName == 'supervisor_id').choices,
        {'manager': 'Scoped Supervisor'},
      );
      expect(
        backend.functionCalls.where((c) => c['action'] == 'report'),
        isEmpty,
      );
    },
  );

  testWidgets(
    'username login installs an Auth session through the SDK and clears the password',
    (tester) async {
      final backend = WorkspaceTestBackend();
      Map<String, dynamic>? login;
      bool refreshed = false;
      final client = await clientFor(tester, (request) async {
        if (request.url.path.endsWith('/personnel-auth')) {
          login = jsonDecode(request.body) as Map<String, dynamic>;
          return http.Response(
            jsonEncode({
              'session': {'refresh_token': 'test-refresh'},
            }),
            200,
            headers: {'content-type': 'application/json'},
          );
        }
        if (request.url.path.endsWith('/token')) {
          refreshed =
              request.url.queryParameters['grant_type'] == 'refresh_token';
        }
        return backend.handle(request);
      });
      await tester.pumpWidget(MaterialApp(home: LoginPage(client: client)));
      await tester.enterText(find.byType(TextFormField).at(0), ' Person.One ');
      await tester.enterText(
        find.byType(TextFormField).at(1),
        'Chosen-password-123',
      );
      await tester.tap(find.text('Sign In'));
      await settle(tester);
      expect(login?['identifier'], 'person.one');
      expect(login?['action'], 'login');
      expect(refreshed, isTrue);
      expect(client.auth.currentUser?.id, fixtureUserId);
      expect(
        tester
            .widget<TextFormField>(find.byType(TextFormField).at(1))
            .controller!
            .text,
        isEmpty,
      );
    },
  );
  testWidgets(
    'username recovery directs to setup without requesting email recovery',
    (tester) async {
      var calls = 0;
      final client = await clientFor(tester, (_) async {
        calls++;
        return http.Response('{}', 400);
      });
      await tester.pumpWidget(MaterialApp(home: LoginPage(client: client)));
      await tester.enterText(find.byType(TextFormField).at(0), 'person.one');
      await tester.tap(find.text('Forgot Password?'));
      await tester.pumpAndSettle();
      expect(find.textContaining('For username accounts'), findsOneWidget);
      expect(calls, 0);
      await tester.ensureVisible(
        find.text('Set up or recover Personnel account'),
      );
      await tester.tap(find.text('Set up or recover Personnel account'));
      await tester.pumpAndSettle();
      expect(find.byType(AccountSetupPage), findsOneWidget);
    },
  );
  testWidgets(
    'Personnel setup validates confirmation, clears secrets on background, and requires server completion',
    (tester) async {
      var calls = 0;
      Map<String, dynamic>? submitted;
      final client = await clientFor(tester, (request) async {
        calls++;
        submitted = jsonDecode(request.body) as Map<String, dynamic>;
        return http.Response(
          '{"completed":true}',
          200,
          headers: {'content-type': 'application/json'},
        );
      });
      await tester.pumpWidget(
        MaterialApp(home: AccountSetupPage(client: client)),
      );
      final fields = find.byType(TextFormField);
      await tester.enterText(fields.at(0), 'person.one');
      await tester.enterText(fields.at(1), 'a' * 43);
      await tester.enterText(fields.at(2), 'Chosen-password-123');
      await tester.enterText(fields.at(3), 'different');
      await tester.tap(find.text('Set my password'));
      await tester.pumpAndSettle();
      expect(calls, 0);
      expect(find.text('Passwords must match.'), findsOneWidget);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      await tester.pump();
      for (var i = 1; i < 4; i++) {
        expect(
          tester.widget<TextFormField>(fields.at(i)).controller!.text,
          isEmpty,
        );
      }
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.enterText(fields.at(1), 'a' * 43);
      await tester.enterText(fields.at(2), 'Chosen-password-123');
      await tester.enterText(fields.at(3), 'Chosen-password-123');
      await tester.tap(find.text('Set my password'));
      await settle(tester);
      expect(calls, 1);
      expect(submitted?['action'], 'redeem');
      expect(client.auth.currentSession, isNull);
      expect(find.textContaining('Password set.'), findsOneWidget);
    },
  );
  testWidgets(
    'Supervisor username creation permits blank email and shows an expiring code only once',
    (tester) async {
      String? copied;
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'Clipboard.setData') {
            copied = (call.arguments as Map)['text'] as String;
          }
          return null;
        },
      );
      addTearDown(() {
        tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        );
      });
      final backend = WorkspaceTestBackend()..addSite();
      Map<String, dynamic>? sent;
      final client = await clientFor(tester, (request) async {
        if (request.url.path.endsWith('/manage-users')) {
          sent = jsonDecode(request.body) as Map<String, dynamic>;
          if (sent?['action'] == 'list') {
            return http.Response(
              '{"users":[]}',
              200,
              headers: {'content-type': 'application/json'},
            );
          }
          return http.Response(
            jsonEncode({
              'setup_code': 'a' * 43,
              'identifier': 'person.one',
              'expires_at': '2026-10-18T10:00:00Z',
            }),
            200,
            headers: {'content-type': 'application/json'},
          );
        }
        return backend.handle(request);
      });
      await tester.runAsync(
        () => client.auth.signInWithPassword(
          email: 'manager@example.test',
          password: 'test-only',
        ),
      );
      await tester.pumpWidget(
        MaterialApp(
          home: PeoplePage(
            client: client,
            access: WorkspaceAccess(
              fullName: backend.fullName,
              roles: backend.roles,
            ),
            agencyId: fixtureAgencyId,
            agencyName: 'Agency',
            sites: backend.sites,
            embedded: true,
          ),
        ),
      );
      await settle(tester);
      expect(find.text('Create Personnel with username'), findsNothing);
      await tester.tap(find.text('Add'));
      await tester.pumpAndSettle();
      final fields = find.byType(TextFormField);
      await tester.enterText(fields.at(0), 'New Person');
      await tester.enterText(fields.at(1), 'person.one');
      await tester.enterText(fields.at(3), 'Supervisor-password');
      await tester.ensureVisible(find.text('Create account'));
      await tester.tap(find.text('Create account'));
      await settle(tester);
      expect(sent?['email'], isNull);
      expect(sent?['site_id'], fixtureSiteId);
      expect(sent?['action'], 'create_personnel');
      expect(find.byType(AccountCodePage), findsOneWidget);
      expect(find.text('a' * 43), findsOneWidget);
      await tester.tap(find.text('a' * 43));
      await tester.pump();
      expect(copied, 'a' * 43);
      expect(find.text('Code copied'), findsOneWidget);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      await tester.pump();
      expect(find.text('a' * 43), findsNothing);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();
      expect(find.text('a' * 43), findsNothing);
    },
  );
  testWidgets(
    'Admin assigns a previously unassigned Personnel to a real workplace',
    (tester) async {
      final backend = WorkspaceTestBackend()..addSite();
      final person = <String, dynamic>{
        'user_id': '00000000-0000-0000-0000-000000000002',
        'full_name': 'Pending Worker',
        'role': 'personnel',
        'agency_id': null,
        'site_id': null,
        'is_active': false,
        'is_unassigned': true,
        'account_status': 'active',
        'can_delete': true,
      };
      backend.managedUsers.add(person);
      Map<String, dynamic>? sent;
      final client = await clientFor(tester, (request) async {
        if (request.url.path.endsWith('/manage-users')) {
          final body = jsonDecode(request.body) as Map<String, dynamic>;
          if (body['action'] == 'assign_personnel') {
            sent = body;
            person.addAll({
              'agency_id': body['agency_id'],
              'site_id': body['site_id'],
              'is_active': true,
              'is_unassigned': false,
            });
            return http.Response(
              '{"updated":true}',
              200,
              headers: {'content-type': 'application/json'},
            );
          }
        }
        return backend.handle(request);
      });
      await tester.pumpWidget(
        MaterialApp(
          home: PeoplePage(
            client: client,
            agencyId: fixtureAgencyId,
            agencyName: 'Agency',
            sites: backend.sites,
            embedded: true,
            access: const WorkspaceAccess(
              fullName: 'Admin',
              roles: [
                {'role': 'admin', 'agency_id': null, 'site_id': null},
              ],
            ),
          ),
        ),
      );
      await settle(tester);
      expect(find.text('Unassigned'), findsOneWidget);
      await tester.tap(find.byTooltip('Manage Pending Worker'));
      await settle(tester);
      await tester.tap(find.text('Assign workplace'));
      await settle(tester);
      await tester.tap(find.byType(DropdownButtonFormField<String>).first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Test Manpower').last);
      await tester.pumpAndSettle();
      await tester.tap(find.byType(DropdownButtonFormField<String>).last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Test Workplace').last);
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byType(TextFormField).last,
        'Admin-test-password',
      );
      await tester.ensureVisible(find.text('Save'));
      await tester.tap(find.text('Save'));
      await settle(tester);
      expect(sent?['agency_id'], fixtureAgencyId);
      expect(sent?['site_id'], fixtureSiteId);
      expect(find.text('Unassigned'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('unassigned setup code keeps null scope after a company exists', (
    tester,
  ) async {
    final backend = WorkspaceTestBackend()..addSite();
    backend.managedUsers.add({
      'user_id': '00000000-0000-0000-0000-000000000002',
      'full_name': 'Pending Code',
      'role': 'personnel',
      'agency_id': null,
      'site_id': null,
      'is_active': false,
      'is_unassigned': true,
      'account_status': 'setup_pending',
      'can_delete': true,
    });
    Map<String, dynamic>? sent;
    final client = await clientFor(tester, (request) async {
      if (request.url.path.endsWith('/manage-users')) {
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        if (body['action'] == 'issue_account_code') {
          sent = body;
          return http.Response(
            jsonEncode({
              'setup_code': 'a' * 43,
              'identifier': 'pending.code',
              'expires_at': '2026-10-20T10:00:00Z',
            }),
            200,
            headers: {'content-type': 'application/json'},
          );
        }
      }
      return backend.handle(request);
    });
    await tester.pumpWidget(
      MaterialApp(
        home: PeoplePage(
          client: client,
          agencyId: fixtureAgencyId,
          agencyName: 'Agency',
          sites: backend.sites,
          embedded: true,
          access: const WorkspaceAccess(
            fullName: 'Admin',
            roles: [
              {'role': 'admin', 'agency_id': null, 'site_id': null},
            ],
          ),
        ),
      ),
    );
    await settle(tester);
    await tester.tap(find.byTooltip('Manage Pending Code'));
    await settle(tester);
    await tester.tap(find.text('Setup / recovery code'));
    await settle(tester);
    await tester.enterText(
      find.byType(TextFormField).first,
      'Replacement code requested',
    );
    await tester.enterText(
      find.byType(TextFormField).last,
      'Admin-test-password',
    );
    await tester.ensureVisible(find.text('Issue one-time code'));
    await tester.tap(find.text('Issue one-time code'));
    await settle(tester);
    expect(sent?['agency_id'], isNull);
    expect(sent?['site_id'], isNull);
    expect(find.byType(AccountCodePage), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  for (final kind in ['supervisor', 'username', 'email']) {
    testWidgets('Admin creates unassigned $kind account without a company', (
      tester,
    ) async {
      final backend = WorkspaceTestBackend();
      Map<String, dynamic>? sent;
      final client = await clientFor(tester, (request) async {
        if (request.url.path.endsWith('/manage-users')) {
          final body = jsonDecode(request.body) as Map<String, dynamic>;
          if (['invite', 'create_personnel'].contains(body['action'])) {
            sent = body;
            return http.Response(
              jsonEncode(
                kind == 'username'
                    ? {
                        'setup_code': 'a' * 43,
                        'identifier': 'pending.person',
                        'expires_at': '2026-10-20T10:00:00Z',
                      }
                    : {'result': 'unassigned', 'invitation_sent': true},
              ),
              200,
              headers: {'content-type': 'application/json'},
            );
          }
        }
        return backend.handle(request);
      });
      await tester.pumpWidget(
        MaterialApp(
          home: PeoplePage(
            client: client,
            agencyId: null,
            agencyName: 'Unassigned people',
            sites: const [],
            embedded: true,
            access: const WorkspaceAccess(
              fullName: 'Admin',
              roles: [
                {'role': 'admin', 'agency_id': null, 'site_id': null},
              ],
            ),
          ),
        ),
      );
      await settle(tester);
      await tester.tap(find.text('Add'));
      await tester.pumpAndSettle();
      if (kind != 'supervisor') {
        await tester.tap(find.text('Supervisor').last);
        await tester.pumpAndSettle();
        await tester.tap(find.text('Personnel').last);
        await tester.pumpAndSettle();
        if (kind == 'email') {
          await tester.ensureVisible(find.text('Username and password'));
          await tester.tap(find.text('Username and password'));
          await tester.pumpAndSettle();
          await tester.tap(find.text('Email invitation').last);
          await tester.pumpAndSettle();
        }
      }
      final fields = find.byType(TextFormField);
      await tester.enterText(fields.at(0), 'Pending Person');
      await tester.enterText(
        fields.at(1),
        kind == 'username' ? 'pending.person' : 'pending@example.test',
      );
      await tester.enterText(fields.last, 'Admin-test-password');
      final submit = find.text(
        kind == 'username' ? 'Create account' : 'Send invite',
      );
      await tester.ensureVisible(submit);
      await tester.tap(submit);
      await settle(tester);
      expect(sent?['agency_id'], isNull);
      expect(sent?['site_id'], isNull);
      expect(
        sent?['action'],
        kind == 'username' ? 'create_personnel' : 'invite',
      );
      expect(sent?['full_name'], 'Pending Person');
      expect(tester.takeException(), isNull);
    });
  }

  for (final form in ['add', 'recovery', 'delete', 'access']) {
    testWidgets('cancelling an empty $form form does not refresh Team', (
      tester,
    ) async {
      final backend = WorkspaceTestBackend()..addSite();
      backend.managedUsers.add({
        'user_id': '00000000-0000-0000-0000-000000000002',
        'full_name': 'Test Personnel',
        'email': 'person@example.test',
        'role': 'personnel',
        'site_id': fixtureSiteId,
        'is_active': true,
        'can_delete': true,
        'account_status': 'active',
      });
      final client = await clientFor(tester, backend.handle);
      await tester.runAsync(
        () => client.auth.signInWithPassword(
          email: 'manager@example.test',
          password: 'test-only',
        ),
      );
      await tester.pumpWidget(
        MaterialApp(
          home: PeoplePage(
            client: client,
            access: WorkspaceAccess(
              fullName: backend.fullName,
              roles: backend.roles,
            ),
            agencyId: fixtureAgencyId,
            agencyName: 'Agency',
            sites: backend.sites,
            embedded: true,
          ),
        ),
      );
      await settle(tester);
      final initialCalls = backend.functionCalls.length;
      if (form == 'add') {
        await tester.tap(find.text('Add'));
      } else {
        await tester.tap(find.byTooltip('Manage Test Personnel'));
        await tester.pumpAndSettle();
        final action = find.text(switch (form) {
          'recovery' => 'Setup / recovery code',
          'delete' => 'Delete account permanently',
          _ => 'Suspend access',
        });
        await tester.ensureVisible(action);
        await tester.tap(action);
      }
      await tester.pumpAndSettle();
      final submit = find.text(switch (form) {
        'add' => 'Create account',
        'recovery' => 'Issue one-time code',
        'delete' => 'Delete account permanently',
        _ => 'Suspend',
      });
      await tester.ensureVisible(submit);
      await tester.tap(submit);
      await tester.pumpAndSettle();
      expect(backend.functionCalls.length, initialCalls);
      expect(find.byType(CircularProgressIndicator), findsNothing);
      await tester.ensureVisible(find.text('Cancel'));
      await tester.tap(find.text('Cancel'));
      await tester.pump();
      expect(find.byType(CircularProgressIndicator), findsNothing);
      await settle(tester);
      expect(backend.functionCalls.length, initialCalls);
      expect(find.text('Test Personnel'), findsOneWidget);
    });
  }
  testWidgets(
    'account code reports a clipboard failure without losing the code',
    (tester) async {
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'Clipboard.setData') {
            throw PlatformException(code: 'clipboard_unavailable');
          }
          return null;
        },
      );
      addTearDown(() {
        tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        );
      });
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpWidget(
        MaterialApp(
          home: AccountCodePage(
            grant: {
              'setup_code': 'a' * 43,
              'identifier': 'person.one',
              'expires_at': '2026-10-18T10:00:00Z',
            },
          ),
        ),
      );
      await tester.tap(find.byIcon(Icons.copy));
      await tester.pump();
      expect(
        find.text('Could not copy code. Please try again.'),
        findsOneWidget,
      );
      expect(find.text('a' * 43), findsOneWidget);
      expect(find.text('Code copied'), findsNothing);
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'activity checklist editor sends stable item identities with its workflow operation',
    (tester) async {
      final backend = WorkspaceTestBackend()..addSite();
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
      final client = await clientFor(tester, backend.handle);
      await tester.runAsync(
        () => client.auth.signInWithPassword(
          email: 'manager@example.test',
          password: 'test-only',
        ),
      );
      await tester.pumpWidget(
        MaterialApp(
          home: SchedulingPage(
            client: client,
            access: WorkspaceAccess(
              fullName: backend.fullName,
              roles: backend.roles,
            ),
            agencyId: fixtureAgencyId,
            sites: backend.sites,
          ),
        ),
      );
      await settle(tester);
      await tester.tap(find.text('Add').first);
      await tester.pumpAndSettle();
      final site = find.byType(DropdownButtonFormField<String>).first;
      await tester.tap(site);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Test Workplace').last);
      await tester.pumpAndSettle();
      final fields = find.byType(TextFormField);
      await tester.enterText(fields.at(0), 'Cleaning');
      await tester.enterText(fields.last, 'Wipe counters\nEmpty bins');
      await tester.ensureVisible(find.text('Save'));
      await tester.tap(find.text('Save'));
      await settle(tester);
      final call = backend.functionCalls.singleWhere(
        (call) => call['action'] == 'activity_save',
      );
      expect((call['checklist_items'] as List).map((item) => item['label']), [
        'Wipe counters',
        'Empty bins',
      ]);
      expect(call.containsKey('checklist_lines'), isFalse);
    },
  );
}
