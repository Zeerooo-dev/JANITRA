import 'package:supabase_flutter/supabase_flutter.dart';

String accountLabel(User? user) {
  final email = user?.email ?? '';
  if (!email.toLowerCase().endsWith('@personnel.janitra.invalid')) return email;
  return user?.userMetadata?['username'] is String
      ? user!.userMetadata!['username'] as String
      : 'Personnel account';
}
