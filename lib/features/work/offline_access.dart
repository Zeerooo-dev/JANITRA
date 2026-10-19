import 'package:cryptography/cryptography.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'local_work_store.dart';

Future<String> _fingerprint(Session session) async =>
    (await Sha256().hash(session.accessToken.codeUnits)).bytes
        .map((b) => b.toRadixString(16).padLeft(2, '0'))
        .join();
Future<void> saveOfflineAccess(
  Session session, {
  LocalWorkStore? store,
  List<String> scopes = const [],
  DateTime? now,
}) async {
  if (session.expiresAt == null) return;
  final verified = (now ?? DateTime.now()).toUtc().millisecondsSinceEpoch;
  await (store ?? LocalWorkStore(session.user.id)).put(
    'personal_access_proof',
    {
      'owner': session.user.id,
      'token_hash': await _fingerprint(session),
      'expires_at': session.expiresAt,
      'verified_at': verified,
      'last_seen': verified,
      'valid_until': [
        session.expiresAt! * 1000,
        verified + const Duration(hours: 8).inMilliseconds,
      ].reduce((a, b) => a < b ? a : b),
      'scopes': scopes,
    },
  );
}

Future<bool> mayReadOfflinePersonalWork(
  Session session, {
  LocalWorkStore? store,
  DateTime? now,
}) async {
  final current = (now ?? DateTime.now()).toUtc().millisecondsSinceEpoch;
  if (session.expiresAt == null || session.expiresAt! * 1000 <= current) {
    return false;
  }
  try {
    final local = store ?? LocalWorkStore(session.user.id);
    final proof = await local.get('personal_access_proof');
    final allowed =
        proof?['owner'] == session.user.id &&
        proof?['token_hash'] == await _fingerprint(session) &&
        proof?['expires_at'] == session.expiresAt &&
        proof?['verified_at'] is int &&
        proof?['valid_until'] is int &&
        proof?['last_seen'] is int &&
        current >= (proof!['last_seen'] as int) - 5000 &&
        current < (proof['valid_until'] as int) &&
        (proof['valid_until'] as int) <=
            (proof['verified_at'] as int) +
                const Duration(hours: 8).inMilliseconds;
    if (allowed) {
      await local.put('personal_access_proof', {
        ...proof,
        'last_seen': current,
      });
    }
    return allowed;
  } catch (_) {
    return false;
  }
}
