import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

bool verificationUnavailable(Object error) =>
    error is SocketException ||
    error is TimeoutException ||
    error is http.ClientException ||
    error is AuthRetryableFetchException ||
    (error is AuthApiException &&
        (int.tryParse(error.statusCode ?? '') ?? 0) >= 500) ||
    (error is FunctionException && error.status >= 500) ||
    (error is PostgrestException &&
        [
          '503',
          '502',
          '504',
          'PGRST000',
          'PGRST001',
          'PGRST002',
        ].contains(error.code));

class AccessUnavailable implements Exception {
  const AccessUnavailable();
  @override
  String toString() =>
      'Reconnect and verify workplace access before continuing.';
}

class AccessPolicy extends ChangeNotifier {
  AccessPolicy._(this.client);
  static final _policies = Expando<AccessPolicy>();
  static AccessPolicy of(SupabaseClient client) =>
      _policies[client] ??= AccessPolicy._(client);
  final SupabaseClient client;
  bool enforced = false,
      verified = false,
      degraded = false,
      cacheView = false,
      cacheAllowed = false;
  String? owner, token;
  VoidCallback? retry;
  Future<void> Function()? openCache, signOut;

  void accept(Session session) {
    owner = session.user.id;
    token = session.accessToken;
    verified = true;
    degraded = false;
    cacheAllowed = false;
    notifyListeners();
  }

  void block({bool preserveContext = false, bool personalCache = false}) {
    verified = false;
    degraded = preserveContext;
    cacheAllowed = personalCache;
    if (!preserveContext) cacheView = false;
    notifyListeners();
  }

  void showCache(bool value) {
    cacheView = value;
    notifyListeners();
  }

  void requireVerified() {
    if (!enforced) return;
    final session = client.auth.currentSession;
    if (!verified ||
        session == null ||
        session.user.id != owner ||
        session.accessToken != token ||
        session.expiresAt == null ||
        session.expiresAt! * 1000 <= DateTime.now().millisecondsSinceEpoch) {
      throw const AccessUnavailable();
    }
  }
}

class ConnectivityShield extends StatelessWidget {
  const ConnectivityShield({
    super.key,
    required this.client,
    required this.child,
  });
  final SupabaseClient client;
  final Widget child;
  @override
  Widget build(BuildContext context) {
    final policy = AccessPolicy.of(client);
    return AnimatedBuilder(
      animation: policy,
      builder: (context, _) => Stack(
        children: [
          child,
          if (policy.degraded && !policy.cacheView) ...[
            const Positioned.fill(
              child: ModalBarrier(dismissible: false, color: Color(0x22000000)),
            ),
            Positioned(
              left: 16,
              right: 16,
              top: MediaQuery.paddingOf(context).top + 12,
              child: Material(
                elevation: 4,
                borderRadius: BorderRadius.circular(12),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Text(
                        'Connection unavailable',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'Your last verified screen is preserved. Online actions are paused until access is verified again.',
                      ),
                      Wrap(
                        spacing: 8,
                        children: [
                          TextButton(
                            onPressed: policy.retry,
                            child: const Text('Retry connection'),
                          ),
                          if (policy.cacheAllowed)
                            TextButton(
                              onPressed: policy.openCache,
                              child: const Text('Open offline work'),
                            ),
                          TextButton(
                            onPressed: policy.signOut,
                            child: const Text('Sign out'),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
