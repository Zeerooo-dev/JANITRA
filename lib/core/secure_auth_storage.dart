import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class SecureAuthStorage extends LocalStorage {
  SecureAuthStorage(String host) : _key = 'janitra.$host.session';

  final String _key;
  static const _storage = FlutterSecureStorage();

  @override
  Future<void> initialize() async {}

  @override
  Future<bool> hasAccessToken() => _storage.containsKey(key: _key);

  @override
  Future<String?> accessToken() => _storage.read(key: _key);

  @override
  Future<void> removePersistedSession() => _storage.delete(key: _key);

  @override
  Future<void> persistSession(String persistSessionString) =>
      _storage.write(key: _key, value: persistSessionString);
}

class SecurePkceStorage extends GotrueAsyncStorage {
  static const _storage = FlutterSecureStorage();

  @override
  Future<String?> getItem({required String key}) =>
      _storage.read(key: 'janitra.pkce.$key');

  @override
  Future<void> removeItem({required String key}) =>
      _storage.delete(key: 'janitra.pkce.$key');

  @override
  Future<void> setItem({required String key, required String value}) =>
      _storage.write(key: 'janitra.pkce.$key', value: value);
}
