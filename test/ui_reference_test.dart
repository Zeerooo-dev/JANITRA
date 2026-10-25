import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/testing.dart';
import 'package:janitra/app.dart';
import 'package:janitra/core/appearance_settings.dart';
import 'package:janitra/features/work/task_page.dart';
import 'package:janitra/features/work/task_record.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'fixtures/workspace_backend.dart';
import 'workflows_test.dart' show sampleTask;

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
  Future<void> open(
    WidgetTester tester,
    WorkspaceTestBackend backend, {
    bool login = true,
    double scale = 1,
  }) async {
    tester.view.physicalSize = Size(scale == 1 ? 390 : 320, 844);
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = scale;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    final client = (await tester.runAsync(
      () async => SupabaseClient(
        'https://example.supabase.co',
        'test',
        httpClient: MockClient(backend.handle),
        authOptions: const AuthClientOptions(autoRefreshToken: false),
      ),
    ))!;
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox());
      await tester.runAsync(client.dispose);
    });
    if (login) {
      await tester.runAsync(
        () => client.auth.signInWithPassword(
          email: 'test@example.test',
          password: 'test-only',
        ),
      );
    }
    final appearance = AppearanceSettings()..motion = MotionPreference.off;
    addTearDown(appearance.dispose);
    await tester.pumpWidget(
      RepaintBoundary(
        key: const ValueKey('screen'),
        child: JanitraApp(client: client, appearance: appearance),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> capture(WidgetTester tester, String name) async {
    expect(tester.takeException(), isNull);
    await expectLater(
      find.byKey(const ValueKey('screen')),
      matchesGoldenFile('goldens/$name.png'),
    );
  }

  Future<void> tab(WidgetTester tester, String name) async {
    await tester.tap(
      find.descendant(
        of: find.byType(NavigationBar),
        matching: find.text(name),
      ),
    );
    for (var i = 0; i < 4; i++) {
      await tester.pump();
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
    }
    await tester.pumpAndSettle();
  }

  WorkspaceTestBackend fixture({bool employee = false}) {
    final backend = WorkspaceTestBackend()..addSite();
    backend.fullName = employee ? 'Test Personnel' : 'Test Supervisor';
    if (employee) {
      backend.roles = [
        {
          'role': 'personnel',
          'agency_id': fixtureAgencyId,
          'site_id': fixtureSiteId,
        },
      ];
    }
    final task = sampleTask(
      status: employee ? 'SCHEDULED' : 'PENDING_APPROVAL',
    );
    task.data['work_date'] = dateOnly(manilaNow());
    backend.workTables['task_work_view'] = [task.data];
    return backend;
  }

  testWidgets('reference login renders and validation stays usable', (
    tester,
  ) async {
    await open(tester, fixture(), login: false);
    await tester.runAsync(
      () => precacheImage(
        const AssetImage('assets/icons/janitra_launcher_1024.png'),
        tester.element(find.byType(Scaffold)),
      ),
    );
    await tester.pumpAndSettle();
    await capture(tester, 'login');
    await tester.tap(find.text('Sign In'));
    await tester.pumpAndSettle();
    expect(find.text('Enter your username or email address.'), findsOneWidget);
  });
  testWidgets(
    'Supervisor reference navigation retains task filter and state across tabs and resume',
    (tester) async {
      await open(tester, fixture());
      await capture(tester, 'supervisor-home');
      await tab(tester, 'Tasks');
      final state = tester.state(find.byType(TasksPage));
      await capture(tester, 'supervisor-tasks');
      await tester.tap(
        find.widgetWithText(OutlinedButton, 'Needs Confirmation'),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('All History'));
      await tester.pumpAndSettle();
      await tab(tester, 'Team');
      await capture(tester, 'team-empty');
      await tab(tester, 'Reports');
      await capture(tester, 'reports');
      await tab(tester, 'Tasks');
      expect(tester.state(find.byType(TasksPage)), same(state));
      expect(
        find.widgetWithText(OutlinedButton, 'All History'),
        findsOneWidget,
      );
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump(const Duration(milliseconds: 350));
      await tester.pumpAndSettle();
      expect(tester.state(find.byType(TasksPage)), same(state));
      expect(find.text('Account connected'), findsNothing);
      await tester.tap(find.text('Review Task'));
      await tester.pumpAndSettle();
      expect(find.byType(TaskDetailsPage), findsOneWidget);
      await capture(tester, 'supervisor-detail');
    },
  );
  for (final scale in [1.0, 2.0]) {
    testWidgets('Admin setup screen reflows at text scale $scale', (
      tester,
    ) async {
      final backend = WorkspaceTestBackend()
        ..roles = [
          {'role': 'admin', 'agency_id': null, 'site_id': null},
        ]
        ..agencies.clear();
      await open(tester, backend, scale: scale);
      expect(find.text('Set up your workspace'), findsOneWidget);
      await capture(
        tester,
        scale == 1 ? 'admin-home-setup' : 'admin-home-setup-large-text',
      );
      await tester.ensureVisible(find.text('Manage unassigned people'));
      await tester.tap(find.text('Manage unassigned people'));
      for (var i = 0; i < 4; i++) {
        await tester.pump();
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 50)),
        );
      }
      await tester.pumpAndSettle();
      expect(find.text('Add'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('Employee reference home tasks details and profile', (
    tester,
  ) async {
    await open(tester, fixture(employee: true));
    await capture(tester, 'employee-home');
    await tab(tester, 'My Tasks');
    await capture(tester, 'employee-tasks');
    await tester.tap(find.text('Test cleaning'));
    await tester.pumpAndSettle();
    await capture(tester, 'employee-detail');
    await tester.pageBack();
    await tester.pumpAndSettle();
    await tab(tester, 'Profile');
    await capture(tester, 'employee-profile');
    expect(find.text('Change Agency'), findsNothing);
  });
  for (final employee in [false, true]) {
    testWidgets(
      '${employee ? 'Employee' : 'Supervisor'} screens reflow at 320px and 200 percent',
      (tester) async {
        await open(tester, fixture(employee: employee), scale: 2);
        expect(tester.takeException(), isNull);
        await tab(tester, employee ? 'My Tasks' : 'Tasks');
        await capture(
          tester,
          employee
              ? 'employee-tasks-large-text'
              : 'supervisor-tasks-large-text',
        );
        await tester.tap(find.text('Test cleaning'));
        await tester.pumpAndSettle();
        await tester.ensureVisible(
          find.text(employee ? 'Mark as Done' : 'Confirm Work'),
        );
        expect(tester.takeException(), isNull);
      },
    );
  }
}
