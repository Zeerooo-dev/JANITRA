import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/testing.dart';
import 'package:janitra/app.dart';
import 'package:janitra/core/access_policy.dart';
import 'package:janitra/features/authentication/login_page.dart';
import 'package:janitra/features/authentication/reset_password_page.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'fixtures/workspace_backend.dart';

void main() {
  void foreground(WidgetTester tester) {
    if (tester.binding.lifecycleState == AppLifecycleState.paused) {
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    }
    if (tester.binding.lifecycleState == AppLifecycleState.hidden) {
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    }
    if (tester.binding.lifecycleState != AppLifecycleState.resumed) {
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    }
  }

  Future<SupabaseClient> open(
    WidgetTester tester,
    WorkspaceTestBackend backend, {
    bool recovery = true,
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
      final pending = backend.pendingAuth;
      if (pending != null && !pending.isCompleted) pending.complete();
      await tester.pumpWidget(const SizedBox());
      foreground(tester);
      await tester.runAsync(client.dispose);
    });
    if (recovery) {
      final parameters = Uri(
        queryParameters: {
          'access_token': backend.sessionToken,
          'refresh_token': 'test-recovery-refresh',
          'expires_in': '3600',
          'token_type': 'bearer',
          'type': 'recovery',
        },
      ).query;
      await tester.runAsync(
        () => client.auth.getSessionFromUrl(
          Uri.parse('janitra://auth-callback/#$parameters'),
        ),
      );
    } else {
      backend.passwordNeeded = true;
      await tester.runAsync(
        () => client.auth.signInWithPassword(
          email: 'worker@example.test',
          password: 'test-session-only',
        ),
      );
    }
    await tester.pumpWidget(JanitraApp(client: client));
    await tester.pumpAndSettle();
    expect(find.byType(ResetPasswordPage), findsOneWidget);
    expect(AccessPolicy.of(client).verified, isFalse);
    return client;
  }

  int reads(WorkspaceTestBackend backend) => backend.requests
      .where((r) => r.url.path == '/auth/v1/user' && r.method == 'GET')
      .length;

  void focusInterruption(WidgetTester tester) {
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
  }

  for (final recovery in [true, false]) {
    testWidgets(
      '${recovery ? 'recovery' : 'initial password setup'} preserves typing and form identity through keyboard focus checks',
      (tester) async {
        final backend = WorkspaceTestBackend();
        await open(tester, backend, recovery: recovery);
        final state = tester.state(find.byType(ResetPasswordPage));
        final fields = find.byType(TextFormField);
        final before = reads(backend);
        addTearDown(tester.view.resetViewInsets);
        await tester.enterText(fields.at(0), 'Chosen-password-123');
        tester.view.viewInsets = const FakeViewPadding(bottom: 280);
        await tester.pumpAndSettle();
        expect(reads(backend), before);
        final pending = Completer<void>();
        backend.pendingAuth = pending;
        for (final text in ['C', 'Chosen', 'Chosen-password-123']) {
          await tester.enterText(fields.at(0), text);
          focusInterruption(tester);
          await tester.pump(const Duration(milliseconds: 350));
          expect(find.byType(ResetPasswordPage), findsOneWidget);
          expect(tester.state(find.byType(ResetPasswordPage)), same(state));
          expect(
            tester.widget<TextFormField>(fields.at(0)).controller!.text,
            text,
          );
          expect(find.text('Checking your access'), findsNothing);
          expect(find.byType(NavigationBar), findsNothing);
        }
        expect(reads(backend), before + 1);
        await tester.enterText(fields.at(1), 'Chosen-password-123');
        pending.complete();
        await tester.pumpAndSettle();
        expect(tester.state(find.byType(ResetPasswordPage)), same(state));
        for (final field in tester.widgetList<TextFormField>(fields)) {
          expect(field.controller!.text, 'Chosen-password-123');
        }
      },
    );
  }

  testWidgets(
    'token refresh and stale authorization responses cannot replace the recovery form',
    (tester) async {
      final backend = WorkspaceTestBackend();
      final client = await open(tester, backend);
      final state = tester.state(find.byType(ResetPasswordPage));
      final fields = find.byType(TextFormField);
      await tester.enterText(fields.at(0), 'Chosen-password-123');
      final pending = Completer<void>();
      backend.pendingAuth = pending;
      focusInterruption(tester);
      await tester.pump(const Duration(milliseconds: 350));
      backend.accessToken = 'fresh-test-recovery-token';
      await tester.runAsync(client.auth.refreshSession);
      await tester.pump();
      expect(tester.state(find.byType(ResetPasswordPage)), same(state));
      pending.complete();
      await tester.pumpAndSettle();
      expect(tester.state(find.byType(ResetPasswordPage)), same(state));
      expect(
        tester.widget<TextFormField>(fields.at(0)).controller!.text,
        'Chosen-password-123',
      );
      expect(AccessPolicy.of(client).verified, isFalse);
      expect(find.byType(NavigationBar), findsNothing);
    },
  );

  testWidgets(
    'recovery still saves the chosen password and signs out after a focus check',
    (tester) async {
      final backend = WorkspaceTestBackend();
      final client = await open(tester, backend);
      final fields = find.byType(TextFormField);
      await tester.enterText(fields.at(0), 'Chosen-password-123');
      await tester.enterText(fields.at(1), 'Chosen-password-123');
      focusInterruption(tester);
      await tester.pump(const Duration(milliseconds: 350));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Save Password'));
      await tester.tap(find.text('Save Password'));
      await tester.pumpAndSettle();
      final updates = backend.requests
          .where((r) => r.url.path == '/auth/v1/user' && r.method == 'PUT')
          .toList();
      expect(updates, hasLength(1));
      expect(
        jsonDecode(updates.single.body)['password'],
        'Chosen-password-123',
      );
      expect(client.auth.currentSession, isNull);
      expect(find.byType(LoginPage), findsOneWidget);
      expect(find.byType(ResetPasswordPage), findsNothing);
    },
  );

  testWidgets(
    'expiry during a delayed recovery check closes the form and ignores the stale result',
    (tester) async {
      final backend = WorkspaceTestBackend();
      final client = await open(tester, backend);
      await tester.enterText(
        find.byType(TextFormField).first,
        'Chosen-password-123',
      );
      final pending = Completer<void>();
      backend
        ..pendingAuth = pending
        ..accessToken = 'expiring-test-recovery-token'
        ..tokenExpiresAt = DateTime.now().millisecondsSinceEpoch ~/ 1000 + 3;
      await tester.runAsync(client.auth.refreshSession);
      await tester.pump();
      await tester.pump(const Duration(seconds: 4));
      await tester.pumpAndSettle();
      expect(find.byType(ResetPasswordPage), findsNothing);
      expect(find.textContaining('session has expired'), findsOneWidget);
      pending.complete();
      await tester.pumpAndSettle();
      expect(find.byType(ResetPasswordPage), findsNothing);
      expect(AccessPolicy.of(client).verified, isFalse);
    },
  );

  for (final failure in ['rejected session', 'offline', 'sign out']) {
    testWidgets(
      '$failure still closes the recovery form and protected access',
      (tester) async {
        final backend = WorkspaceTestBackend();
        final client = await open(tester, backend);
        await tester.enterText(
          find.byType(TextFormField).first,
          'Chosen-password-123',
        );
        if (failure == 'sign out') {
          await tester.runAsync(client.auth.signOut);
        } else {
          backend.rejectedSession = failure == 'rejected session';
          backend.offline = failure == 'offline';
          focusInterruption(tester);
          await tester.pump(const Duration(milliseconds: 350));
        }
        await tester.pumpAndSettle();
        expect(find.byType(ResetPasswordPage), findsNothing);
        expect(find.byType(NavigationBar), findsNothing);
        expect(AccessPolicy.of(client).verified, isFalse);
        if (failure == 'sign out') {
          expect(find.byType(LoginPage), findsOneWidget);
        }
      },
    );
  }

  for (final background in [
    AppLifecycleState.hidden,
    AppLifecycleState.paused,
    AppLifecycleState.detached,
  ]) {
    testWidgets(
      '$background clears recovery secrets without discarding its form',
      (tester) async {
        final backend = WorkspaceTestBackend();
        await open(tester, backend);
        final state = tester.state(find.byType(ResetPasswordPage));
        final fields = find.byType(TextFormField);
        for (var index = 0; index < 2; index++) {
          await tester.enterText(fields.at(index), 'Chosen-password-123');
        }
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.inactive,
        );
        tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
        if (background != AppLifecycleState.hidden) {
          tester.binding.handleAppLifecycleStateChanged(
            AppLifecycleState.paused,
          );
        }
        if (background == AppLifecycleState.detached) {
          tester.binding.handleAppLifecycleStateChanged(
            AppLifecycleState.detached,
          );
        }
        await tester.pump();
        for (final field in tester.widgetList<TextFormField>(fields)) {
          expect(field.controller!.text, isEmpty);
        }
        foreground(tester);
        await tester.pump(const Duration(milliseconds: 350));
        await tester.pumpAndSettle();
        expect(tester.state(find.byType(ResetPasswordPage)), same(state));
      },
    );
  }
}
