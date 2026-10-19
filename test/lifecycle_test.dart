import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/testing.dart';
import 'package:janitra/app.dart';
import 'package:janitra/core/access_policy.dart';
import 'package:janitra/core/access_notice.dart';
import 'package:janitra/features/workspace/workspace_page.dart';
import 'package:janitra/features/workspace/name_editor.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'fixtures/workspace_backend.dart';

void main() {
  Future<SupabaseClient> open(
    WidgetTester tester,
    WorkspaceTestBackend backend, {
    bool settle = true,
  }) async {
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
    if (settle) await tester.pumpAndSettle();
    return client;
  }

  void switchApps(WidgetTester tester) {
    for (final state in [
      AppLifecycleState.inactive,
      AppLifecycleState.hidden,
      AppLifecycleState.paused,
      AppLifecycleState.hidden,
      AppLifecycleState.inactive,
      AppLifecycleState.resumed,
    ]) {
      tester.binding.handleAppLifecycleStateChanged(state);
    }
  }

  Future<void> resume(WidgetTester tester) async {
    switchApps(tester);
    await tester.pump(const Duration(milliseconds: 350));
  }

  Future<void> profile(WidgetTester tester) async {
    await tester.tap(find.byTooltip('Profile'));
    await tester.pumpAndSettle();
  }

  int authReads(WorkspaceTestBackend backend) => backend.requests
      .where(
        (request) =>
            request.url.path == '/auth/v1/user' && request.method == 'GET',
      )
      .length;

  void detail(WidgetTester tester) {
    Navigator.of(tester.element(find.byType(WorkspacePage))).push<void>(
      MaterialPageRoute(
        builder: (_) => const Scaffold(body: Text('Protected detail')),
      ),
    );
  }

  testWidgets(
    'initial validation stays closed until authorization is verified',
    (tester) async {
      final backend = WorkspaceTestBackend()..pendingAuth = Completer<void>();
      await open(tester, backend, settle: false);
      await tester.pump();
      expect(find.text('Checking your access'), findsOneWidget);
      expect(find.byType(LinearProgressIndicator), findsOneWidget);
      expect(find.byType(NavigationBar), findsNothing);
      backend.pendingAuth!.complete();
      await tester.pumpAndSettle();
      expect(find.text('Supervisor workspace'), findsOneWidget);
    },
  );

  testWidgets('routine resume preserves a pushed protected route', (
    tester,
  ) async {
    final backend = WorkspaceTestBackend();
    await open(tester, backend);
    detail(tester);
    await tester.pumpAndSettle();
    await resume(tester);
    await tester.pumpAndSettle();
    expect(find.text('Protected detail'), findsOneWidget);
    expect(find.text('Account connected'), findsNothing);
  });

  testWidgets(
    'slow resume keeps the workspace, Profile tab and unsaved dialog mounted',
    (tester) async {
      final backend = WorkspaceTestBackend()..addSite();
      await open(tester, backend);
      await profile(tester);
      final workspace = tester.state(find.byType(WorkspacePage));
      await tester.tap(find.text('Edit Your Name'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextFormField), 'Unsaved name');
      backend.pendingAuth = Completer<void>();
      await resume(tester);
      expect(authReads(backend), 2);
      expect(find.text('Account connected'), findsNothing);
      expect(find.byType(NameEditor), findsOneWidget);
      expect(
        tester
            .widget<TextFormField>(find.byType(TextFormField))
            .controller!
            .text,
        'Unsaved name',
      );
      expect(tester.state(find.byType(WorkspacePage)), same(workspace));
      await tester.pump(const Duration(seconds: 5));
      expect(find.text('Account connected'), findsNothing);
      backend.pendingAuth!.complete();
      await tester.pumpAndSettle();
      expect(tester.state(find.byType(WorkspacePage)), same(workspace));
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(find.text('Your account'), findsOneWidget);
    },
  );

  testWidgets(
    'rapid resumes debounce, and concurrent manual refreshes share one check',
    (tester) async {
      final backend = WorkspaceTestBackend();
      await open(tester, backend);
      await profile(tester);
      backend.pendingAuth = Completer<void>();
      for (var i = 0; i < 5; i++) {
        switchApps(tester);
        await tester.pump(const Duration(milliseconds: 50));
      }
      expect(authReads(backend), 1);
      await tester.pump(const Duration(milliseconds: 350));
      expect(authReads(backend), 2);
      final refresh = find.text('Refresh Workplace Access');
      await tester.ensureVisible(refresh);
      await tester.tap(refresh);
      await tester.tap(refresh);
      await resume(tester);
      expect(authReads(backend), 2);
      backend.pendingAuth!.complete();
      await tester.pumpAndSettle();
      expect(authReads(backend), 2);
      expect(find.text('Your account'), findsOneWidget);
    },
  );

  for (final denied in ['session', 'suspended', 'role']) {
    testWidgets(
      'confirmed $denied invalidation closes protected routes immediately',
      (tester) async {
        final backend = WorkspaceTestBackend()..addSite();
        await open(tester, backend);
        detail(tester);
        await tester.pumpAndSettle();
        switch (denied) {
          case 'session':
            backend.rejectedSession = true;
          case 'suspended':
            backend.active = false;
          case 'role':
            backend.roles = [];
        }
        await resume(tester);
        await tester.pumpAndSettle();
        expect(find.text('Protected detail'), findsNothing);
        expect(find.byType(NavigationBar), findsNothing);
        expect(find.text('Account connected'), findsNothing);
      },
    );
  }

  testWidgets(
    'a reduced role scope discards protected navigation and old management state',
    (tester) async {
      final backend = WorkspaceTestBackend()..addSite();
      await open(tester, backend);
      detail(tester);
      await tester.pumpAndSettle();
      backend.roles = [
        {
          'role': 'personnel',
          'agency_id': fixtureAgencyId,
          'site_id': fixtureSiteId,
        },
      ];
      await resume(tester);
      await tester.pumpAndSettle();
      expect(find.text('Protected detail'), findsNothing);
      expect(find.text('My Tasks'), findsOneWidget);
      expect(find.text('Workplaces'), findsNothing);
    },
  );

  testWidgets(
    'offline validation preserves the route but blocks operations until verified',
    (tester) async {
      final backend = WorkspaceTestBackend();
      final client = await open(tester, backend);
      detail(tester);
      await tester.pumpAndSettle();
      backend.offline = true;
      await resume(tester);
      await tester.pumpAndSettle();
      expect(find.text('Protected detail'), findsOneWidget);
      expect(find.text('Connection unavailable'), findsOneWidget);
      final before = backend.requests.length;
      await expectLater(
        invokeProtected(client, 'workflow', body: {'action': 'approve'}),
        throwsA(isA<AccessUnavailable>()),
      );
      expect(backend.requests.length, before);
      backend.offline = false;
      await tester.tap(find.text('Retry connection'));
      await tester.pumpAndSettle();
      expect(find.text('Protected detail'), findsOneWidget);
      expect(find.text('Connection unavailable'), findsNothing);
      expect(AccessPolicy.of(client).verified, isTrue);
    },
  );

  testWidgets(
    'timeout closes access and a late response cannot restore revoked authorization',
    (tester) async {
      final backend = WorkspaceTestBackend();
      await open(tester, backend);
      final late = Completer<void>();
      backend.pendingAuth = late;
      await resume(tester);
      await tester.pump(const Duration(seconds: 16));
      await tester.pumpAndSettle();
      expect(find.byType(NavigationBar), findsOneWidget);
      expect(find.text('Connection unavailable'), findsOneWidget);
      backend.pendingAuth = null;
      backend.roles = [];
      await tester.tap(find.text('Retry connection'));
      await tester.pumpAndSettle();
      late.complete();
      await tester.pumpAndSettle();
      expect(find.byType(NavigationBar), findsNothing);
      expect(find.text('Workspace access pending'), findsOneWidget);
    },
  );

  testWidgets(
    'sign-out during validation closes detail and ignores the previous response',
    (tester) async {
      final backend = WorkspaceTestBackend();
      final client = await open(tester, backend);
      detail(tester);
      await tester.pumpAndSettle();
      backend.pendingAuth = Completer<void>();
      await resume(tester);
      await tester.runAsync(client.auth.signOut);
      await tester.pumpAndSettle();
      expect(find.text('Protected detail'), findsNothing);
      expect(find.text('Welcome to JANITRA'), findsOneWidget);
      backend.pendingAuth!.complete();
      await tester.pumpAndSettle();
      expect(find.byType(WorkspacePage), findsNothing);
    },
  );

  testWidgets(
    'token refresh supersedes an old check without remounting the workspace',
    (tester) async {
      final backend = WorkspaceTestBackend();
      final client = await open(tester, backend);
      await profile(tester);
      final workspace = tester.state(find.byType(WorkspacePage));
      final late = Completer<void>();
      backend.pendingAuth = late;
      await resume(tester);
      backend.pendingAuth = null;
      backend.accessToken = 'test-refreshed-token';
      await tester.runAsync(client.auth.refreshSession);
      await tester.pump();
      late.complete();
      await tester.pumpAndSettle();
      expect(authReads(backend), 3);
      expect(tester.state(find.byType(WorkspacePage)), same(workspace));
      expect(find.text('Your account'), findsOneWidget);
    },
  );
  testWidgets(
    'late authorization failure for an older token does not remove a newly verified route',
    (tester) async {
      final backend = WorkspaceTestBackend();
      final client = await open(tester, backend);
      detail(tester);
      await tester.pumpAndSettle();
      backend.pendingFunction = Completer<void>();
      final operation = invokeProtected(
        client,
        'workflow',
        body: {'action': 'approve'},
      );
      final rejected = expectLater(
        operation,
        throwsA(isA<FunctionException>()),
      );
      await tester.pump();
      backend.accessToken = 'renewed-token';
      await tester.runAsync(client.auth.refreshSession);
      await tester.pumpAndSettle();
      backend.pendingAuth = Completer<void>();
      backend.functionError = {
        'code': 'authorization_changed',
        'message': 'Old request failed',
      };
      backend.pendingFunction!.complete();
      for (var i = 0; i < 4; i++) {
        await tester.pump();
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 40)),
        );
      }
      expect(find.text('Protected detail'), findsOneWidget);
      backend.pendingAuth!.complete();
      await tester.pumpAndSettle();
      await rejected;
      expect(find.text('Protected detail'), findsOneWidget);
    },
  );
  testWidgets(
    'a degraded foreground workspace revalidates automatically when the connection returns',
    (tester) async {
      final backend = WorkspaceTestBackend();
      await open(tester, backend);
      detail(tester);
      await tester.pumpAndSettle();
      backend.offline = true;
      await resume(tester);
      await tester.pumpAndSettle();
      expect(find.text('Connection unavailable'), findsOneWidget);
      backend.offline = false;
      await tester.pump(const Duration(seconds: 31));
      await tester.pumpAndSettle();
      expect(find.text('Connection unavailable'), findsNothing);
      expect(find.text('Protected detail'), findsOneWidget);
    },
  );

  testWidgets(
    'a different authenticated account cannot retain the previous protected route',
    (tester) async {
      final backend = WorkspaceTestBackend();
      final client = await open(tester, backend);
      final oldWorkspace = tester.state(find.byType(WorkspacePage));
      detail(tester);
      await tester.pumpAndSettle();
      backend.accessToken = 'other-account-token';
      backend.userId = '00000000-0000-0000-0000-000000000002';
      await tester.runAsync(
        () => client.auth.signInWithPassword(
          email: 'other@example.test',
          password: 'test-only',
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Protected detail'), findsNothing);
      expect(
        tester.state(find.byType(WorkspacePage)),
        isNot(same(oldWorkspace)),
      );
    },
  );

  testWidgets(
    'token expiry during a slow check blocks access and ignores its late response',
    (tester) async {
      final backend = WorkspaceTestBackend()
        ..tokenExpiresAt = DateTime.now().millisecondsSinceEpoch ~/ 1000 + 3;
      await open(tester, backend);
      backend.pendingAuth = Completer<void>();
      await resume(tester);
      await tester.pump(const Duration(seconds: 4));
      await tester.pumpAndSettle();
      expect(find.byType(NavigationBar), findsNothing);
      expect(find.textContaining('session has expired'), findsOneWidget);
      backend.pendingAuth!.complete();
      await tester.pumpAndSettle();
      expect(find.byType(NavigationBar), findsNothing);
    },
  );

  testWidgets(
    'token renewal cancels the previous expiry guard and retains navigation',
    (tester) async {
      final backend = WorkspaceTestBackend()
        ..tokenExpiresAt = DateTime.now().millisecondsSinceEpoch ~/ 1000 + 3;
      final client = await open(tester, backend);
      await profile(tester);
      final workspace = tester.state(find.byType(WorkspacePage));
      backend.tokenExpiresAt = null;
      backend.accessToken = 'renewed-session-token';
      await tester.runAsync(client.auth.refreshSession);
      await tester.pumpAndSettle();
      await tester.pump(const Duration(seconds: 4));
      expect(tester.state(find.byType(WorkspacePage)), same(workspace));
      expect(find.text('Your account'), findsOneWidget);
    },
  );
}
