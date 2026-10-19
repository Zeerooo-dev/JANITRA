import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:janitra/app.dart';
import 'package:janitra/core/auth_callback.dart';
import 'package:janitra/core/supabase_config.dart';
import 'package:janitra/features/authentication/reset_password_page.dart';
import 'package:janitra/features/authentication/company_setup_page.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class _MemoryPkceStorage extends GotrueAsyncStorage {
  final _values = <String, String>{};
  @override
  Future<String?> getItem({required String key}) async => _values[key];
  @override
  Future<void> removeItem({required String key}) async {
    _values.remove(key);
  }

  @override
  Future<void> setItem({required String key, required String value}) async {
    _values[key] = value;
  }
}

void main() {
  test(
    'recovery callbacks accept the configured URL and reject lookalikes',
    () {
      expect(isAuthCallback(Uri.parse(authRedirectUrl)), isTrue);
      expect(
        isAuthCallback(Uri.parse('$authRedirectUrl?code=test-code')),
        isTrue,
      );
      for (final url in [
        'https://auth-callback/',
        'janitra://different-host/',
        'janitra://auth-callback/other',
        'janitra://auth-callback.evil/',
        'janitra://attacker@auth-callback/',
        'janitra://auth-callback:1234/',
      ]) {
        expect(isAuthCallback(Uri.parse(url)), isFalse, reason: url);
      }
    },
  );
  Future<SupabaseClient> clientWith(
    WidgetTester tester,
    MockClient httpClient,
  ) async => (await tester.runAsync(
    () async => SupabaseClient(
      'https://example.supabase.co',
      'sb_publishable_test',
      httpClient: httpClient,
      authOptions: AuthClientOptions(
        autoRefreshToken: false,
        pkceAsyncStorage: _MemoryPkceStorage(),
      ),
    ),
  ))!;

  test('client configuration rejects privileged and malformed keys', () {
    expect(
      SupabaseConfig('https://example.supabase.co', 'sb_publishable_test').url,
      'https://example.supabase.co',
    );
    String jwt(String role) =>
        'header.${base64Url.encode(utf8.encode(jsonEncode({'role': role})))}.signature';
    expect(
      SupabaseConfig('https://example.supabase.co', jwt('anon')).key,
      jwt('anon'),
    );
    for (final key in ['sb_secret_test', jwt('service_role'), 'broken', '']) {
      expect(
        () => SupabaseConfig('https://example.supabase.co', key),
        throwsFormatException,
      );
    }
    expect(
      () => SupabaseConfig('http://example.supabase.co', 'sb_publishable_test'),
      throwsFormatException,
    );
  });

  testWidgets('empty credentials show validation and send no request', (
    tester,
  ) async {
    var requests = 0;
    final client = await clientWith(
      tester,
      MockClient((_) async {
        requests++;
        return http.Response('{}', 400);
      }),
    );
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox());
      await tester.runAsync(client.dispose);
    });
    await tester.pumpWidget(JanitraApp(client: client));
    await tester.pumpAndSettle();
    expect(
      find.image(const AssetImage('assets/icons/janitra_launcher_1024.png')),
      findsOneWidget,
    );
    expect(find.byIcon(Icons.check_rounded), findsNothing);
    expect(find.byTooltip('Appearance'), findsNothing);
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    expect(
      tester
          .widget<EditableText>(find.byType(EditableText).at(0))
          .focusNode
          .hasFocus,
      isTrue,
    );
    expect(
      tester.widget<EditableText>(find.byType(EditableText).at(1)).obscureText,
      isTrue,
    );
    await tester.tap(find.byTooltip('Show password'));
    await tester.pump();
    expect(
      tester.widget<EditableText>(find.byType(EditableText).at(1)).obscureText,
      isFalse,
    );
    await tester.tap(find.byTooltip('Hide password'));
    await tester.pump();
    await tester.tap(find.text('Sign In'));
    await tester.pumpAndSettle();
    expect(find.text('Enter your username or email address.'), findsOneWidget);
    expect(find.text('Enter your password.'), findsOneWidget);
    expect(requests, 0);
    expect(find.text('Account connected'), findsNothing);
  });

  testWidgets(
    'rejected credentials cannot enter the app; password is cleared',
    (tester) async {
      http.Request? request;
      final client = await clientWith(
        tester,
        MockClient((r) async {
          request = r;
          return http.Response(
            '{"code":"invalid_credentials","msg":"Invalid login credentials"}',
            400,
            headers: {'content-type': 'application/json'},
          );
        }),
      );
      addTearDown(() async {
        await tester.pumpWidget(const SizedBox());
        await tester.runAsync(client.dispose);
      });
      await tester.pumpWidget(JanitraApp(client: client));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byType(TextFormField).at(0),
        'worker@example.com',
      );
      await tester.enterText(find.byType(TextFormField).at(1), 'test-password');
      await tester.tap(find.text('Sign In'));
      await tester.pumpAndSettle();
      expect(request?.url.path, '/auth/v1/token');
      expect(request?.url.queryParameters['grant_type'], 'password');
      expect(find.textContaining('Could not sign in.'), findsOneWidget);
      expect(
        tester
            .widget<TextFormField>(find.byType(TextFormField).at(1))
            .controller!
            .text,
        isEmpty,
      );
      expect(find.text('Account connected'), findsNothing);
    },
  );

  testWidgets(
    'loading prevents duplicate sign-in; authenticated account can sign out',
    (tester) async {
      final response = Completer<http.Response>();
      var signIns = 0;
      final client = await clientWith(
        tester,
        MockClient((r) async {
          if (r.url.path.endsWith('/logout')) return http.Response('', 204);
          if (r.url.path.endsWith('/user') && r.method == 'GET') {
            return http.Response(
              jsonEncode({
                'id': '00000000-0000-0000-0000-000000000001',
                'aud': 'authenticated',
                'role': 'authenticated',
                'email': 'worker@example.com',
                'created_at': '2026-10-12T00:00:00Z',
              }),
              200,
              headers: {'content-type': 'application/json'},
              request: r,
            );
          }
          if (r.url.path.endsWith('/needs_company_setup') ||
              r.url.path.endsWith('/needs_password_setup')) {
            return http.Response(
              'false',
              200,
              headers: {'content-type': 'application/json'},
              request: r,
            );
          }
          if (r.url.path.endsWith('/profiles') ||
              r.url.path.endsWith('/role_assignments')) {
            return http.Response(
              '[]',
              200,
              headers: {
                'content-type': 'application/json',
                'content-range': '*/0',
              },
              request: r,
            );
          }
          signIns++;
          return response.future;
        }),
      );
      addTearDown(() async {
        await tester.pumpWidget(const SizedBox());
        await tester.runAsync(client.dispose);
      });
      await tester.pumpWidget(JanitraApp(client: client));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byType(TextFormField).at(0),
        'worker@example.com',
      );
      await tester.enterText(find.byType(TextFormField).at(1), 'test-password');
      await tester.tap(find.text('Sign In'));
      await tester.pump();
      expect(
        tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
        isNull,
      );
      expect(find.text('Please wait…'), findsOneWidget);
      response.complete(
        http.Response(
          jsonEncode({
            'access_token': 'test-token',
            'refresh_token': 'test-refresh',
            'token_type': 'bearer',
            'expires_in': 3600,
            'user': {
              'id': '00000000-0000-0000-0000-000000000001',
              'aud': 'authenticated',
              'role': 'authenticated',
              'email': 'worker@example.com',
              'app_metadata': {},
              'user_metadata': {'role': 'supervisor'},
              'created_at': '2026-10-12T00:00:00Z',
            },
          }),
          200,
          headers: {'content-type': 'application/json'},
        ),
      );
      await tester.pumpAndSettle();
      expect(signIns, 1);
      expect(find.text('Workspace access pending'), findsOneWidget);
      expect(find.text('Approve Work'), findsNothing);
      await tester.ensureVisible(find.text('Sign out'));
      await tester.tap(find.text('Sign out'));
      await tester.pumpAndSettle();
      expect(find.text('Welcome to JANITRA'), findsOneWidget);
    },
  );

  testWidgets(
    'recovery uses the Android callback and does not reveal account existence',
    (tester) async {
      http.Request? request;
      final client = await clientWith(
        tester,
        MockClient((r) async {
          request = r;
          return http.Response(
            '{}',
            200,
            headers: {'content-type': 'application/json'},
          );
        }),
      );
      addTearDown(() async {
        await tester.pumpWidget(const SizedBox());
        await tester.runAsync(client.dispose);
      });
      await tester.pumpWidget(JanitraApp(client: client));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byType(TextFormField).at(0),
        'worker@example.com',
      );
      await tester.ensureVisible(find.text('Forgot Password?'));
      await tester.tap(find.text('Forgot Password?'));
      await tester.pumpAndSettle();
      expect(request?.url.path, '/auth/v1/recover');
      expect(
        request?.url.queryParameters['redirect_to'],
        'janitra://auth-callback/',
      );
      expect(jsonDecode(request!.body)['code_challenge'], isNotEmpty);
      expect(find.textContaining('If an account exists'), findsOneWidget);
    },
  );

  testWidgets('invited Supervisor sets a password before company setup', (
    tester,
  ) async {
    final user = {
      'id': '00000000-0000-0000-0000-000000000001',
      'aud': 'authenticated',
      'role': 'authenticated',
      'email': 'invited@example.test',
      'app_metadata': <String, dynamic>{},
      'user_metadata': <String, dynamic>{},
      'created_at': '2026-10-12T00:00:00Z',
    };
    var passwordWrites = 0;
    var signOuts = 0;
    final client = await clientWith(
      tester,
      MockClient((request) async {
        Object? body;
        var status = 200;
        if (request.url.path.endsWith('/token')) {
          body = {
            'access_token': 'test-token',
            'refresh_token': 'test-refresh',
            'token_type': 'bearer',
            'expires_in': 3600,
            'user': user,
          };
        } else if (request.url.path.endsWith('/user') &&
            request.method == 'GET') {
          body = user;
        } else if (request.url.path.endsWith('/needs_company_setup')) {
          body = true;
        } else if (request.url.path.endsWith('/needs_password_setup')) {
          body = passwordWrites < 2;
        } else if (request.url.path.endsWith('/user') &&
            request.method == 'PUT') {
          passwordWrites++;
          expect(jsonDecode(request.body)['password'], 'new-test-password');
          status = passwordWrites == 1 ? 400 : 200;
          body = passwordWrites == 1 ? {'msg': 'Test rejected update'} : user;
        } else if (request.url.path.endsWith('/logout')) {
          signOuts++;
          return http.Response('', 204, request: request);
        } else {
          fail('Unexpected request ${request.method} ${request.url.path}');
        }
        return http.Response(
          jsonEncode(body),
          status,
          request: request,
          headers: {'content-type': 'application/json'},
        );
      }),
    );
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox());
      await tester.runAsync(client.dispose);
    });
    await tester.runAsync(
      () => client.auth.signInWithPassword(
        email: 'invited@example.test',
        password: 'test-session-only',
      ),
    );
    await tester.pumpWidget(JanitraApp(client: client));
    await tester.pumpAndSettle();
    expect(find.text('Set Your Password'), findsOneWidget);
    expect(find.text('Register Company'), findsNothing);
    for (var attempt = 0; attempt < 2; attempt++) {
      await tester.enterText(
        find.byType(TextFormField).at(0),
        'new-test-password',
      );
      await tester.enterText(
        find.byType(TextFormField).at(1),
        'new-test-password',
      );
      await tester.tap(find.text('Save Password'));
      await tester.pumpAndSettle();
      if (attempt == 0) {
        expect(find.text('Set Your Password'), findsOneWidget);
        expect(
          find.textContaining('Could not finish changing your password.'),
          findsOneWidget,
        );
        for (final field in tester.widgetList<TextFormField>(
          find.byType(TextFormField),
        )) {
          expect(field.controller!.text, isEmpty);
        }
      }
    }
    expect(passwordWrites, 2);
    expect(signOuts, 0);
    expect(find.text('Register Company'), findsOneWidget);
  });

  testWidgets('reset rejects short and mismatched passwords without a write', (
    tester,
  ) async {
    var requests = 0;
    final client = await clientWith(
      tester,
      MockClient((_) async {
        requests++;
        return http.Response('{}', 400);
      }),
    );
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox());
      await tester.runAsync(client.dispose);
    });
    await tester.pumpWidget(
      MaterialApp(home: ResetPasswordPage(client: client)),
    );
    await tester.enterText(find.byType(TextFormField).at(0), 'short');
    await tester.enterText(find.byType(TextFormField).at(1), 'different');
    await tester.tap(find.text('Save Password'));
    await tester.pumpAndSettle();
    expect(find.text('Passwords do not match.'), findsOneWidget);
    expect(find.text('Use at least 12 characters.'), findsWidgets);
    expect(requests, 0);
  });

  testWidgets('company setup validates names before contacting the backend', (
    tester,
  ) async {
    var requests = 0;
    final client = await clientWith(
      tester,
      MockClient((_) async {
        requests++;
        return http.Response('{}', 400);
      }),
    );
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox());
      await tester.runAsync(client.dispose);
    });
    await tester.pumpWidget(
      MaterialApp(
        home: CompanySetupPage(
          client: client,
          onSaved: () => fail('Invalid setup accepted'),
        ),
      ),
    );
    expect(
      find.image(const AssetImage('assets/icons/janitra_launcher_1024.png')),
      findsOneWidget,
    );
    await tester.tap(find.text('Register Company'));
    await tester.pumpAndSettle();
    expect(find.text('Enter a name.'), findsNWidgets(2));
    expect(requests, 0);
  });

  testWidgets(
    'company setup prevents duplicate writes and retries failures without false success',
    (tester) async {
      final response = Completer<http.Response>();
      var requests = 0;
      var saved = 0;
      http.Request? lastRequest;
      final client = await clientWith(
        tester,
        MockClient((request) async {
          requests++;
          lastRequest = request;
          return requests == 1
              ? response.future
              : http.Response(
                  '"10000000-0000-0000-0000-000000000001"',
                  200,
                  headers: {'content-type': 'application/json'},
                  request: request,
                );
        }),
      );
      addTearDown(() async {
        await tester.pumpWidget(const SizedBox());
        await tester.runAsync(client.dispose);
      });
      await tester.pumpWidget(
        MaterialApp(
          home: CompanySetupPage(client: client, onSaved: () => saved++),
        ),
      );
      await tester.enterText(
        find.byType(TextFormField).at(0),
        ' My Manpower Company ',
      );
      await tester.enterText(
        find.byType(TextFormField).at(1),
        ' First Supervisor ',
      );
      await tester.tap(find.text('Register Company'));
      await tester.pump();
      expect(
        tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
        isNull,
      );
      response.complete(
        http.Response(
          '{"code":"42501","message":"Not authorized"}',
          403,
          headers: {'content-type': 'application/json'},
          request: lastRequest,
        ),
      );
      await tester.pumpAndSettle();
      expect(saved, 0);
      expect(
        find.textContaining('Could not register your company.'),
        findsOneWidget,
      );
      await tester.tap(find.text('Register Company'));
      await tester.pumpAndSettle();
      expect(saved, 1);
      expect(requests, 2);
      expect(lastRequest?.url.path, '/rest/v1/rpc/setup_manpower_company');
      expect(jsonDecode(lastRequest!.body), {
        'company_name': 'My Manpower Company',
        'supervisor_name': 'First Supervisor',
      });
    },
  );

  testWidgets('company setup fits narrow screens at 200 percent text scale', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    final client = await clientWith(
      tester,
      MockClient((_) async => http.Response('{}', 400)),
    );
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox());
      await tester.runAsync(client.dispose);
    });
    await tester.pumpWidget(
      MaterialApp(
        home: CompanySetupPage(client: client, onSaved: () {}),
      ),
    );
    await tester.ensureVisible(find.text('Register Company'));
    await tester.tap(find.text('Register Company'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Sign Out'));
    expect(tester.takeException(), isNull);
  });

  testWidgets('login fits narrow screens at 200 percent text scale', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    final client = await clientWith(
      tester,
      MockClient((_) async => http.Response('{}', 400)),
    );
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox());
      await tester.runAsync(client.dispose);
    });
    await tester.pumpWidget(JanitraApp(client: client));
    await tester.pumpAndSettle();
    expect(
      MediaQuery.textScalerOf(tester.element(find.byType(FilledButton)))
          .scale(16),
      32,
    );
    await tester.ensureVisible(find.text('Sign In'));
    expect(tester.takeException(), isNull);
    expect(
      tester.getSize(find.byType(FilledButton)).height,
      greaterThanOrEqualTo(56),
    );
  });
}
