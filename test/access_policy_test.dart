import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:janitra/core/access_policy.dart';
import 'package:janitra/core/access_notice.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'fixtures/workspace_backend.dart';

void main() {
  test('transport failures and 503 are unavailable, authorization failures are not', () {
    for (final error in [
      const SocketException('offline'),
      TimeoutException('timeout'),
      http.ClientException('offline'),
      const AuthApiException('unavailable', statusCode: '503'),
      const FunctionException(
        status: 503,
        details: {'code': 'verification_unavailable'},
      ),
    ]) {
      expect(verificationUnavailable(error), isTrue);
    }
    for (final error in [
      const AuthApiException('expired', statusCode: '401'),
      const PostgrestException(message: 'denied', code: '42501'),
      const FormatException('invalid'),
      const FunctionException(
        status: 422,
        details: {'code': 'invitation_email_invalid'},
      ),
      const FunctionException(
        status: 422,
        details: {'code': 'invitation_email_restricted'},
      ),
      const FunctionException(
        status: 429,
        details: {'code': 'invitation_rate_limited'},
      ),
    ]) {
      expect(verificationUnavailable(error), isFalse);
    }
  });
  test(
    'email validation failures do not invalidate verified workspace access',
    () async {
      final backend = WorkspaceTestBackend();
      final client = SupabaseClient(
        'https://example.supabase.co',
        'test',
        httpClient: MockClient((request) async {
          if (request.url.path.endsWith('/manage-users')) {
            return http.Response(
              jsonEncode({
                'message': 'The email service rejected this address.',
                'code': 'invitation_email_invalid',
              }),
              422,
              headers: {'content-type': 'application/json'},
            );
          }
          return backend.handle(request);
        }),
        authOptions: const AuthClientOptions(autoRefreshToken: false),
      );
      addTearDown(client.dispose);
      await client.auth.signInWithPassword(
        email: 'test@example.test',
        password: 'test-only',
      );
      final policy = AccessPolicy.of(client)..enforced = true;
      policy.accept(client.auth.currentSession!);
      final notices = <AccessNotice>[];
      final subscription = AccessNotice.events
          .where((event) => identical(event.client, client))
          .listen(notices.add);
      addTearDown(subscription.cancel);
      await expectLater(
        invokeProtected(client, 'manage-users', body: {'action': 'invite'}),
        throwsA(isA<FunctionException>()),
      );
      expect(notices, isEmpty);
      expect(policy.requireVerified, returnsNormally);
    },
  );
  test('blocked and stale-token commands never reach the network', () async {
    final backend = WorkspaceTestBackend();
    final client = SupabaseClient(
      'https://example.supabase.co',
      'test',
      httpClient: MockClient(backend.handle),
      authOptions: const AuthClientOptions(autoRefreshToken: false),
    );
    addTearDown(client.dispose);
    await client.auth.signInWithPassword(
      email: 'test@example.test',
      password: 'test-only',
    );
    final policy = AccessPolicy.of(client)..enforced = true;
    policy.accept(client.auth.currentSession!);
    expect(policy.requireVerified, returnsNormally);
    policy.block(preserveContext: true);
    final before = backend.requests.length;
    await expectLater(
      invokeProtected(client, 'workflow', body: {'action': 'approve'}),
      throwsA(isA<AccessUnavailable>()),
    );
    expect(backend.requests.length, before);
    policy.accept(client.auth.currentSession!);
    backend.accessToken = 'changed-token';
    await client.auth.refreshSession();
    expect(policy.requireVerified, throwsA(isA<AccessUnavailable>()));
    policy.accept(client.auth.currentSession!);
    expect(policy.requireVerified, returnsNormally);
    await client.auth.signOut();
    expect(policy.requireVerified, throwsA(isA<AccessUnavailable>()));
  });
}
