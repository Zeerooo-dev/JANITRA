import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

const fixtureUserId = '00000000-0000-0000-0000-000000000001';
const fixtureAgencyId = '10000000-0000-0000-0000-000000000001';
const fixtureClientId = '20000000-0000-0000-0000-000000000001';
const fixtureSiteId = '30000000-0000-0000-0000-000000000001';

class WorkspaceTestBackend {
  bool failAccess = false,
      failLoads = false,
      rejectWrites = false,
      active = true;
  Completer<void>? pendingWrite;
  Completer<void>? pendingAuth;
  Completer<void>? pendingFunction;
  bool offline = false, rejectedSession = false;
  String accessToken = 'test-token';
  String userId = fixtureUserId;
  int? tokenExpiresAt;
  bool passwordNeeded = false;
  String? assurance;
  final factors = <Map<String, dynamic>>[];
  bool rejectMfa = false;
  Completer<void>? pendingMfa;
  final int _defaultExpiry =
      DateTime.now().millisecondsSinceEpoch ~/ 1000 + 3600;
  String get sessionToken =>
      'eyJhbGciOiJIUzI1NiJ9.${base64Url.encode(utf8.encode(jsonEncode({'aal': assurance ?? 'aal1', 'exp': tokenExpiresAt ?? _defaultExpiry, 'nonce': accessToken}))).replaceAll('=', '')}.test';
  void addFactor({
    String id = 'test-factor',
    String type = 'totp',
    String status = 'verified',
    String name = 'Test authenticator',
  }) {
    factors.add({
      'id': id,
      'factor_type': type,
      'status': status,
      'friendly_name': name,
      'created_at': '2026-10-12T00:00:00Z',
      'updated_at': '2026-10-12T00:00:00Z',
    });
  }

  final functionCalls = <Map<String, dynamic>>[];
  final workTables = <String, List<Map<String, dynamic>>>{};
  Map<String, dynamic>? functionError;
  final managedUsers = <Map<String, dynamic>>[];
  final pinStates = <String, Map<String, dynamic>>{};
  bool allowPinReset = true, rejectPinWrites = false;
  final requests = <http.Request>[];
  final writes = <http.Request>[];
  String fullName = 'Test Supervisor';
  List<Map<String, dynamic>> roles = [
    {'role': 'supervisor', 'agency_id': fixtureAgencyId, 'site_id': null},
  ];
  final agencies = <Map<String, dynamic>>[
    {'id': fixtureAgencyId, 'name': 'Test Manpower'},
  ];
  final clients = <Map<String, dynamic>>[];
  final sites = <Map<String, dynamic>>[];

  Map<String, dynamic> get user => {
    'id': userId,
    'aud': 'authenticated',
    'role': 'authenticated',
    'email': 'worker@example.test',
    'app_metadata': <String, dynamic>{},
    'user_metadata': {'role': 'supervisor'},
    'created_at': '2026-10-12T00:00:00Z',
    'factors': factors,
  };

  void addSite() {
    clients.add({
      'id': fixtureClientId,
      'agency_id': fixtureAgencyId,
      'name': 'Test Client',
    });
    sites.add({
      'id': fixtureSiteId,
      'agency_id': fixtureAgencyId,
      'client_company_id': fixtureClientId,
      'name': 'Test Workplace',
    });
  }

  Future<http.Response> handle(http.Request request) async {
    requests.add(request);
    if (offline) throw http.ClientException('Test offline', request.url);
    final table = request.url.path.split('/').last;
    http.Response response(
      Object? data, {
      int status = 200,
      Map<String, String> headers = const {},
    }) => http.Response(
      jsonEncode(data),
      status,
      request: request,
      headers: {'content-type': 'application/json', ...headers},
    );
    if (table == 'token') {
      return response({
        'access_token': sessionToken,
        'refresh_token': 'test-refresh',
        'token_type': 'bearer',
        'expires_in': 3600,
        'user': user,
      });
    }
    if (table == 'factors' && request.method == 'POST') {
      final body = jsonDecode(request.body) as Map<String, dynamic>;
      addFactor(
        id: 'new-factor',
        status: 'unverified',
        name: body['friendly_name'] as String,
      );
      return response({
        'id': 'new-factor',
        'type': 'totp',
        'totp': {
          'secret': 'TESTONLYSETUPKEY',
          'qr_code': '<svg/>',
          'uri': 'otpauth://totp/test',
        },
      });
    }
    if (table == 'challenge') {
      return response({'id': 'test-challenge', 'expires_at': 2000000000});
    }
    if (table == 'verify') {
      await pendingMfa?.future;
      if (rejectMfa) return response({'msg': 'Invalid MFA code'}, status: 422);
      factors.singleWhere(
        (f) => f['id'] == request.url.path.split('/')[4],
      )['status'] = 'verified';
      assurance = 'aal2';
      return response({
        'access_token': sessionToken,
        'refresh_token': 'test-mfa-refresh',
        'token_type': 'bearer',
        'expires_in': 3600,
        'user': user,
      });
    }
    if (request.url.path.contains('/factors/') && request.method == 'DELETE') {
      factors.removeWhere((f) => f['id'] == table);
      return response({'id': table});
    }
    if (table == 'logout') return http.Response('', 204, request: request);
    if (table == 'user' && request.method == 'GET') {
      final rejected = rejectedSession;
      await pendingAuth?.future;
      return rejected
          ? response({'msg': 'Test expired session'}, status: 401)
          : response(user);
    }
    if (table == 'needs_company_setup') return response(false);
    if (request.url.path.contains('/functions/')) {
      await pendingFunction?.future;
      if (functionError != null) return response(functionError, status: 403);
    }
    if (table == 'needs_password_setup') return response(passwordNeeded);
    if (table == 'user' && request.method == 'PUT') {
      passwordNeeded = false;
      return response(user);
    }
    if (table == 'manage-users') {
      final body = jsonDecode(request.body) as Map<String, dynamic>;
      functionCalls.add(body);
      switch (body['action']) {
        case 'create_agency':
          const id = '10000000-0000-0000-0000-000000000009';
          agencies.add({'id': id, 'name': body['name']});
          return response({'agency_id': id});
        case 'list':
          return response({'users': managedUsers, 'permissions_version': 2});
        case 'invite':
          managedUsers.add({
            'user_id': '00000000-0000-0000-0000-000000000002',
            'full_name': body['full_name'],
            'email': body['email'],
            'role': body['role'],
            'site_id': body['site_id'],
            'is_active': true,
          });
          return response({'result': 'assigned', 'invitation_sent': true});
        case 'set_active':
          managedUsers.singleWhere(
            (user) => user['user_id'] == body['user_id'],
          )['is_active'] = body['is_active'];
          return response({'updated': true});
      }
    }
    if (table == 'manage-pins') {
      final body = jsonDecode(request.body) as Map<String, dynamic>;
      functionCalls.add(body);
      final key = '${body['kind']}:${body['user_id']}';
      if (body['action'] == 'status') {
        return response({
          'configured': pinStates.containsKey(key),
          'changed_at': pinStates[key]?['changed_at'],
          'can_reset': allowPinReset,
        });
      }
      if (rejectPinWrites) {
        return response({
          'message': 'Password confirmation failed.',
        }, status: 401);
      }
      final state = {'configured': true, 'changed_at': '2026-10-12T12:00:00Z'};
      pinStates[key] = state;
      return response(state);
    }
    if (table == 'workflow') {
      final body = jsonDecode(request.body) as Map<String, dynamic>;
      functionCalls.add(body);
      if (['verify', 'approve', 'reject'].contains(body['action'])) {
        final task = workTables['task_work_view']!.singleWhere(
          (t) => t['id'] == body['task_id'],
        );
        if (body['action'] == 'verify') {
          task['verified_at'] = '2026-10-12T02:00:00Z';
          task['verifier_name'] = fullName;
        } else {
          task['status'] = body['action'] == 'approve'
              ? 'APPROVED'
              : 'REJECTED';
          task['decided_at'] = '2026-10-12T03:00:00Z';
          task['decider_name'] = fullName;
        }
        task['version'] = (task['version'] as int) + 1;
        return response({'ok': true, 'task': task});
      }
      return response({'ok': true});
    }
    if (table == 'profiles' && request.method == 'GET') {
      if (failAccess) {
        return response({'message': 'Test access error'}, status: 403);
      }
      return response(
        active
            ? {'id': userId, 'full_name': fullName, 'is_active': true}
            : null,
      );
    }
    if (request.method == 'GET') {
      if ((table == 'role_assignments' && failAccess) ||
          (table != 'role_assignments' && failLoads)) {
        return response({'message': 'Test read error'}, status: 403);
      }
      final all = switch (table) {
        'role_assignments' => roles,
        'agencies' => agencies,
        'client_companies' => clients,
        'sites' => sites,
        'task_work_view' => workTables[table] ?? <Map<String, dynamic>>[],
        'shift_templates' ||
        'shift_segments' ||
        'task_schedule_rules' => workTables[table] ?? <Map<String, dynamic>>[],
        _ =>
          workTables[table] ??
              (throw StateError(
                'Unexpected request ${request.method} ${request.url.path}',
              )),
      };
      final filter = request.url.queryParameters['agency_id'];
      final filtered = all
          .where((row) => filter == null || filter == 'eq.${row['agency_id']}')
          .where(
            (row) =>
                request.url.queryParameters['id'] == null ||
                request.url.queryParameters['id'] == 'eq.${row['id']}',
          )
          .toList();
      if (request.headers['accept']?.contains('vnd.pgrst.object') == true) {
        return response(filtered.single);
      }
      final offset =
          int.tryParse(request.url.queryParameters['offset'] ?? '') ?? 0;
      final limit =
          int.tryParse(request.url.queryParameters['limit'] ?? '') ?? 200;
      final page = filtered.skip(offset).take(limit).toList();
      return response(
        page,
        headers: {
          'content-range': page.isEmpty
              ? '*/${filtered.length}'
              : '$offset-${offset + page.length - 1}/${filtered.length}',
        },
      );
    }
    writes.add(request);
    await pendingWrite?.future;
    if (rejectWrites) {
      return response({
        'code': '23505',
        'message': 'Test duplicate',
      }, status: 409);
    }
    final data = jsonDecode(request.body) as Map<String, dynamic>;
    if (table == 'profiles') {
      fullName = data['full_name'] as String;
      return response({'id': fixtureUserId});
    }
    final rows = switch (table) {
      'agencies' => agencies,
      'client_companies' => clients,
      'sites' => sites,
      _ => throw StateError('Unexpected write $table'),
    };
    if (request.method == 'POST') {
      final row = {'id': '$table-${rows.length + 1}', ...data};
      rows.add(row);
      return response({'id': row['id']}, status: 201);
    }
    final id = request.url.queryParameters['id']?.replaceFirst('eq.', '');
    final row = rows.singleWhere((r) => r['id'] == id);
    row.addAll(data);
    return response({'id': id});
  }
}
