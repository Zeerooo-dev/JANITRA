import 'dart:async';

import 'package:supabase_flutter/supabase_flutter.dart';

import 'access_policy.dart';

class AccessNotice {
  const AccessNotice(this.client, this.userId, this.token, this.code);
  final SupabaseClient client;
  final String? userId, token;
  final String code;
  static final _events = StreamController<AccessNotice>.broadcast(sync: true);
  static Stream<AccessNotice> get events => _events.stream;
}

Future<FunctionResponse> invokeProtected(
  SupabaseClient client,
  String name, {
  required Map<String, dynamic> body,
}) async {
  AccessPolicy.of(client).requireVerified();
  final userId = client.auth.currentUser?.id,
      token = client.auth.currentSession?.accessToken;
  try {
    return await client.functions.invoke(name, body: body);
  } on FunctionException catch (error) {
    final details = error.details;
    if (details is Map &&
        [
          'session_ended',
          'authorization_changed',
          'verification_unavailable',
        ].contains(details['code'])) {
      AccessNotice._events.add(
        AccessNotice(client, userId, token, details['code'] as String),
      );
    } else if (verificationUnavailable(error)) {
      AccessNotice._events.add(
        AccessNotice(client, userId, token, 'verification_unavailable'),
      );
    }
    rethrow;
  } catch (error) {
    if (verificationUnavailable(error)) {
      AccessNotice._events.add(
        AccessNotice(client, userId, token, 'verification_unavailable'),
      );
    }
    rethrow;
  }
}
