import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'app.dart';
import 'core/auth_callback.dart';
import 'core/secure_auth_storage.dart';
import 'core/supabase_config.dart';
import 'core/appearance_settings.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final appearance = AppearanceSettings();
  await appearance.load();
  try {
    final config = SupabaseConfig(
      const String.fromEnvironment('SUPABASE_URL'),
      const String.fromEnvironment('SUPABASE_PUBLISHABLE_KEY'),
    );
    await Supabase.initialize(
      url: config.url,
      publishableKey: config.key,
      debug: false,
      authOptions: FlutterAuthClientOptions(
        localStorage: SecureAuthStorage(Uri.parse(config.url).host),
        pkceAsyncStorage: SecurePkceStorage(),
        detectSessionInUriPredicate: isAuthCallback,
      ),
    );
    runApp(
      JanitraApp(client: Supabase.instance.client, appearance: appearance),
    );
  } catch (_) {
    runApp(JanitraApp(appearance: appearance));
  }
}
