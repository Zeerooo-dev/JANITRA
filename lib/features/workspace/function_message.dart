import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/access_policy.dart';

String functionMessage(Object error) {
  if (error is AccessUnavailable) return error.toString();
  if (error is FunctionsHttpException && error.details is Map) {
    final message = (error.details as Map)['message'];
    if (message is String && message.isNotEmpty) return message;
  }
  return 'Could not complete the request. Check your connection and try again.';
}
