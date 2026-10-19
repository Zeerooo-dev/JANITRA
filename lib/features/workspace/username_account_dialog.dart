import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/access_notice.dart';
import '../work/work_form.dart';
import 'workspace_access.dart';
import 'account_code_page.dart';

Future<bool> manageUsernameAccount(
  BuildContext context, {
  required SupabaseClient client,
  required WorkspaceAccess access,
  required String agencyId,
  required Map<String, dynamic> person,
}) async {
  Map<String, dynamic>? grant;
  if (person['site_id'] is! String ||
      !access.managesSite({'id': person['site_id'], 'agency_id': agencyId})) {
    return false;
  }
  await showModalBottomSheet<bool>(
    context: context,
    enableDrag: false,
    isScrollControlled: true,
    useSafeArea: true,
    constraints: const BoxConstraints(maxWidth: 620),
    builder: (_) => WorkForm(
      sheet: true,
      title: 'Issue account code',
      button: 'Issue one-time code',
      fields: [
        WorkField(
          'purpose',
          'Code purpose',
          value: ['setup_pending'].contains(person['account_status'])
              ? 'setup'
              : 'recovery',
          choices: person['account_status'] == 'setup_pending'
              ? {'setup': 'First password setup'}
              : {'recovery': 'Password recovery'},
        ),
        WorkField(
          'reason',
          'Recovery / reissue reason',
          validate: (v) => v.trim().length < 10
              ? 'Explain the request in at least ten characters.'
              : null,
        ),
        const WorkField(
          'password',
          'Confirm your Supervisor account password',
          secret: true,
        ),
      ],
      save: (values) async {
        final response = await invokeProtected(
          client,
          'manage-users',
          body: {
            ...values,
            'action': 'issue_account_code',
            'agency_id': agencyId,
            'site_id': person['site_id'],
            'user_id': person['user_id'],
          },
        );
        if (response.data is! Map || response.data['setup_code'] is! String) {
          throw const FormatException(
            'No account setup confirmation received.',
          );
        }
        grant = Map<String, dynamic>.from(response.data as Map);
      },
    ),
  );
  if (grant == null) return false;
  if (context.mounted) {
    await Navigator.push(
      context,
      MaterialPageRoute<void>(builder: (_) => AccountCodePage(grant: grant!)),
    );
  }
  return true;
}
