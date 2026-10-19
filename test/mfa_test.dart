import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/testing.dart';
import 'package:janitra/app.dart';
import 'package:janitra/features/authentication/mfa_page.dart';
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

  Future<void> setup(WidgetTester tester) async {
    await tester.tap(find.byTooltip('Profile'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Two-Step Verification'));
    await tester.tap(find.text('Two-Step Verification'));
    await tester.pumpAndSettle();
  }

  testWidgets(
    'configured MFA closes workspace until a six-digit code is verified',
    (tester) async {
      final backend = WorkspaceTestBackend()
        ..assurance = 'aal1'
        ..addFactor();
      await open(tester, backend);
      expect(find.byType(NavigationBar), findsNothing);
      expect(find.byType(MfaPage), findsOneWidget);
      expect(
        backend.requests.any((r) => r.url.path.endsWith('/profiles')),
        false,
      );
      await tester.tap(find.text('Verify Code'));
      await tester.pumpAndSettle();
      expect(find.text('Enter all six digits.'), findsOneWidget);
      await tester.enterText(find.byType(TextFormField), '000123');
      await tester.tap(find.text('Verify Code'));
      await tester.pumpAndSettle();
      expect(find.text('Supervisor workspace'), findsOneWidget);
      expect(
        backend.requests
            .singleWhere((r) => r.url.path.endsWith('/verify'))
            .body,
        contains('000123'),
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('wrong code and network failure stay closed and erase the code', (
    tester,
  ) async {
    final backend = WorkspaceTestBackend()
      ..assurance = 'aal1'
      ..addFactor()
      ..rejectMfa = true;
    await open(tester, backend);
    await tester.enterText(find.byType(TextFormField), '123456');
    await tester.tap(find.text('Verify Code'));
    await tester.pumpAndSettle();
    expect(find.byType(NavigationBar), findsNothing);
    expect(
      tester.widget<TextFormField>(find.byType(TextFormField)).controller!.text,
      isEmpty,
    );
    backend.offline = true;
    await tester.enterText(find.byType(TextFormField), '123456');
    await tester.tap(find.text('Verify Code'));
    await tester.pumpAndSettle();
    expect(
      find.text('Could not connect. Check your connection and retry.'),
      findsOneWidget,
    );
    expect(find.byType(NavigationBar), findsNothing);
    expect(
      tester.widget<TextFormField>(find.byType(TextFormField)).controller!.text,
      isEmpty,
    );
  });

  testWidgets('slow verification prevents duplicate writes and sign-out', (
    tester,
  ) async {
    final backend = WorkspaceTestBackend()
      ..assurance = 'aal1'
      ..addFactor()
      ..pendingMfa = Completer<void>();
    await open(tester, backend);
    await tester.enterText(find.byType(TextFormField), '123456');
    await tester.tap(find.text('Verify Code'));
    await tester.pump();
    await tester.pump();
    expect(
      tester
          .widget<TextButton>(find.widgetWithText(TextButton, 'Sign Out'))
          .onPressed,
      isNull,
    );
    expect(
      tester
          .widget<FilledButton>(find.widgetWithText(FilledButton, 'Verifying…'))
          .onPressed,
      isNull,
    );
    expect(
      backend.requests.where((r) => r.url.path.endsWith('/verify')),
      hasLength(1),
    );
    backend.pendingMfa!.complete();
    await tester.pumpAndSettle();
    expect(find.byType(NavigationBar), findsOneWidget);
  });

  testWidgets('unknown MFA type cannot bypass the gate and can sign out', (
    tester,
  ) async {
    final backend = WorkspaceTestBackend()
      ..assurance = 'aal1'
      ..addFactor(type: 'phone');
    await open(tester, backend);
    expect(find.byType(TextFormField), findsNothing);
    expect(find.textContaining('unavailable in JANITRA'), findsOneWidget);
    await tester.tap(find.text('Sign Out'));
    await tester.pumpAndSettle();
    expect(find.text('Sign In'), findsOneWidget);
  });

  testWidgets(
    'AAL2 restored session and routine resume preserve selected tab',
    (tester) async {
      final backend = WorkspaceTestBackend()
        ..assurance = 'aal2'
        ..addFactor();
      await open(tester, backend);
      await tester.tap(find.byTooltip('Profile'));
      await tester.pumpAndSettle();
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
      await tester.pump(const Duration(milliseconds: 350));
      await tester.pumpAndSettle();
      expect(find.text('Your account'), findsOneWidget);
      expect(find.byType(MfaPage), findsNothing);
    },
  );

  testWidgets(
    'newly configured MFA from server closes an existing protected route',
    (tester) async {
      final backend = WorkspaceTestBackend()..assurance = 'aal1';
      await open(tester, backend);
      await setup(tester);
      backend.addFactor();
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
      await tester.pump(const Duration(milliseconds: 350));
      await tester.pumpAndSettle();
      expect(find.byType(NavigationBar), findsNothing);
      expect(find.byType(MfaPage), findsOneWidget);
      expect(find.text('Verify Code'), findsOneWidget);
    },
  );

  testWidgets(
    'setup keeps secret hidden, cancellation removes only new factor',
    (tester) async {
      final backend = WorkspaceTestBackend();
      await open(tester, backend);
      await setup(tester);
      await tester.tap(find.text('Set Up Authenticator'));
      await tester.pumpAndSettle();
      expect(find.text('TESTONLYSETUPKEY'), findsNothing);
      await tester.ensureVisible(find.text('Show Setup Key'));
      await tester.tap(find.text('Show Setup Key'));
      await tester.pumpAndSettle();
      expect(find.text('TESTONLYSETUPKEY'), findsOneWidget);
      await tester.ensureVisible(find.text('Hide Setup Key'));
      await tester.tap(find.text('Hide Setup Key'));
      await tester.pumpAndSettle();
      expect(find.text('TESTONLYSETUPKEY'), findsNothing);
      await tester.ensureVisible(find.text('Cancel Setup'));
      await tester.tap(find.text('Cancel Setup'));
      await tester.pumpAndSettle();
      expect(backend.factors, isEmpty);
      expect(find.byType(MfaPage), findsNothing);
    },
  );

  testWidgets(
    'abandoned JANITRA setup is cleaned and unrelated factors preserved',
    (tester) async {
      final backend = WorkspaceTestBackend()
        ..addFactor(
          id: 'abandoned',
          status: 'unverified',
          name: 'JANITRA old setup',
        )
        ..addFactor(id: 'other-app', status: 'unverified', name: 'Another app');
      await open(tester, backend);
      await setup(tester);
      await tester.tap(find.text('Set Up Authenticator'));
      await tester.pumpAndSettle();
      expect(backend.factors.map((f) => f['id']), ['other-app', 'new-factor']);
      await tester.enterText(find.byType(TextFormField), '000123');
      await tester.ensureVisible(find.text('Verify Code'));
      await tester.tap(find.text('Verify Code'));
      await tester.pumpAndSettle();
      expect(find.text('Two-step verification is enabled.'), findsOneWidget);
      expect(find.text('TESTONLYSETUPKEY'), findsNothing);
      expect(find.byType(TextFormField), findsNothing);
    },
  );

  testWidgets(
    'existing verified authenticator does not enroll or expose its secret',
    (tester) async {
      final backend = WorkspaceTestBackend()
        ..assurance = 'aal2'
        ..addFactor();
      await open(tester, backend);
      await setup(tester);
      expect(find.text('Two-step verification is enabled.'), findsOneWidget);
      expect(find.text('Set Up Authenticator'), findsNothing);
      expect(
        backend.requests.any(
          (r) => r.url.path.endsWith('/factors') && r.method == 'POST',
        ),
        false,
      );
    },
  );

  testWidgets('enrollment form supports narrow screen and large text', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 1000);
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
      tester.platformDispatcher.clearTextScaleFactorTestValue();
    });
    final backend = WorkspaceTestBackend();
    await open(tester, backend);
    await setup(tester);
    await tester.ensureVisible(find.text('Set Up Authenticator'));
    await tester.tap(find.text('Set Up Authenticator'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Show Setup Key'));
    await tester.tap(find.text('Show Setup Key'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.ensureVisible(find.text('Cancel Setup'));
    await tester.tap(find.text('Cancel Setup'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('setup key and code are hidden when switching to authenticator', (
    tester,
  ) async {
    final backend = WorkspaceTestBackend();
    await open(tester, backend);
    await setup(tester);
    await tester.tap(find.text('Set Up Authenticator'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Show Setup Key'));
    await tester.enterText(find.byType(TextFormField), '123456');
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
    await tester.pump(const Duration(milliseconds: 350));
    await tester.pumpAndSettle();
    expect(find.text('TESTONLYSETUPKEY'), findsNothing);
    expect(
      tester.widget<TextFormField>(find.byType(TextFormField)).controller!.text,
      isEmpty,
    );
    expect(find.text('Show Setup Key'), findsOneWidget);
    expect(find.text('Your account', skipOffstage: false), findsOneWidget);
  });

  testWidgets(
    'multiple authenticators route verification to the selected factor',
    (tester) async {
      final backend = WorkspaceTestBackend()
        ..assurance = 'aal1'
        ..addFactor()
        ..addFactor(id: 'second-factor', name: 'Second authenticator');
      await open(tester, backend);
      await tester.tap(find.byType(DropdownButtonFormField<String>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Second authenticator').last);
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextFormField).last, '000123');
      await tester.tap(find.text('Verify Code'));
      await tester.pumpAndSettle();
      expect(
        backend.requests
            .singleWhere((r) => r.url.path.endsWith('/verify'))
            .url
            .path,
        contains('/second-factor/'),
      );
      expect(find.byType(NavigationBar), findsOneWidget);
    },
  );
  testWidgets(
    'recovery requires MFA and keeps protected routes closed after verification',
    (tester) async {
      final backend = WorkspaceTestBackend()
        ..assurance = 'aal1'
        ..addFactor();
      final client = await open(tester, backend);
      final fragment = Uri(
        queryParameters: {
          'access_token': backend.sessionToken,
          'refresh_token': 'test-refresh',
          'expires_in': '3600',
          'token_type': 'bearer',
          'type': 'recovery',
        },
      ).query;
      await tester.runAsync(
        () => client.auth.getSessionFromUrl(
          Uri.parse('janitra://auth-callback/#$fragment'),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Reset Password'), findsNothing);
      expect(find.text('Verify Code'), findsOneWidget);
      await tester.enterText(find.byType(TextFormField), '123456');
      await tester.tap(find.text('Verify Code'));
      await tester.pumpAndSettle();
      expect(find.text('Reset Password'), findsOneWidget);
      expect(find.byType(NavigationBar), findsNothing);
      expect(find.byTooltip('Show password'), findsNWidgets(2));
      await tester.tap(find.byTooltip('Show password').first);
      await tester.pump();
      expect(
        tester
            .widget<EditableText>(find.byType(EditableText).first)
            .obscureText,
        isFalse,
      );
      expect(
        tester.widget<EditableText>(find.byType(EditableText).last).obscureText,
        isTrue,
      );
      await tester.tap(find.byTooltip('Hide password'));
      await tester.pump();
      await tester.enterText(
        find.byType(TextFormField).first,
        'test-password-long',
      );
      await tester.enterText(
        find.byType(TextFormField).last,
        'test-password-long',
      );
      await tester.tap(find.text('Save Password'));
      await tester.pumpAndSettle();
      expect(find.text('Sign In'), findsOneWidget);
      expect(client.auth.currentSession, isNull);
    },
  );
}
