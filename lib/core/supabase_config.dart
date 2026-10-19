import 'dart:convert';

class SupabaseConfig {
  SupabaseConfig(this.url, this.key) {
    final uri = Uri.tryParse(url);
    if (uri == null ||
        uri.scheme != 'https' ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty ||
        uri.hasQuery ||
        uri.hasFragment) {
      throw const FormatException('A valid HTTPS Supabase URL is required.');
    }
    if (key.startsWith('sb_publishable_') && key.length > 15) return;
    try {
      final parts = key.split('.');
      if (parts.length == 3) {
        final claims = jsonDecode(
          utf8.decode(base64Url.decode(base64Url.normalize(parts[1]))),
        );
        if (claims is Map && claims['role'] == 'anon') return;
      }
    } catch (_) {
      // Malformed keys must follow the same rejection path as privileged keys.
    }
    throw const FormatException(
      'Only a publishable or legacy anon client key is allowed.',
    );
  }

  final String url;
  final String key;
}
