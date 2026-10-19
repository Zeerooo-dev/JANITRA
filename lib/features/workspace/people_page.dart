import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import '../../core/secret_text_form_field.dart';

import 'workspace_access.dart';
import 'function_message.dart';
import 'pin_management_page.dart';
import '../../core/access_notice.dart';
import 'username_account_dialog.dart';
import 'account_code_page.dart';
import 'supervisor_access_sheet.dart';
import '../../core/app_theme.dart';
import '../work/work_form.dart';

class PeoplePage extends StatefulWidget {
  const PeoplePage({
    super.key,
    required this.client,
    required this.access,
    required this.agencyId,
    required this.agencyName,
    required this.sites,
    this.embedded = false,
    this.supervisorManagement = false,
  });
  final SupabaseClient client;
  final bool embedded;
  final bool supervisorManagement;
  final WorkspaceAccess access;
  final String? agencyId;
  final String agencyName;
  final List<Map<String, dynamic>> sites;

  @override
  State<PeoplePage> createState() => _PeoplePageState();
}

class _PeoplePageState extends State<PeoplePage> {
  List<Map<String, dynamic>> _users = [];
  bool _loading = true;
  bool _historySafeDeletion = false;
  String? _error, _notice;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final response = await invokeProtected(
        widget.client,
        'manage-users',
        body: {'action': 'list', 'agency_id': widget.agencyId},
      );
      final users = (response.data as Map<String, dynamic>)['users'] as List;
      if (mounted) {
        _historySafeDeletion =
            (response.data as Map)['permissions_version'] == 2;
        setState(() {
          _users = users
              .cast<Map<String, dynamic>>()
              .where(
                (u) =>
                    u['role'] != 'admin' &&
                    (widget.access.isAdmin ||
                        widget.access.isCompanyWideSupervisor ||
                        u['agency_id'] == null ||
                        u['agency_id'] == widget.agencyId) &&
                    (!widget.supervisorManagement || u['role'] == 'supervisor'),
              )
              .toList();
        });
      }
    } catch (error) {
      if (mounted) setState(() => _error = functionMessage(error));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _invite() async {
    final sites = widget.sites.where(widget.access.managesSite).toList();
    final result = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      enableDrag: false,
      isScrollControlled: true,
      useSafeArea: true,
      constraints: const BoxConstraints(maxWidth: 600),
      builder: (_) => _InviteDialog(
        client: widget.client,
        agencyId: widget.agencyId,
        allowSupervisor: widget.access.isAdmin,
        supervisorOnly: widget.supervisorManagement,
        sites: sites,
      ),
    );
    if (result == null || !mounted) return;
    if (result['setup_code'] is String) {
      await Navigator.push(
        context,
        MaterialPageRoute<void>(builder: (_) => AccountCodePage(grant: result)),
      );
      if (!mounted) return;
      setState(() => _notice = 'Personnel account created.');
      await _load();
      return;
    }
    final outcome = result['result'];
    setState(
      () => _notice = outcome == 'unassigned'
          ? 'Account created. Assign workplace access when a company is ready.'
          : outcome == 'already_assigned'
          ? 'This person already has access.'
          : outcome == 'suspended'
          ? 'This assignment is suspended. Reactivate it in the list.'
          : result['invitation_sent'] == true
          ? 'Invitation sent. The person can set a password from the email link.'
          : 'Access assigned. Ask the person to refresh workplace access.',
    );
    await _load();
  }

  Future<void> _editSupervisor(Map<String, dynamic> user) async {
    if (!widget.access.isAdmin) return;
    try {
      final data = await Future.wait([
        readWorkspaceRows(widget.client.from('agencies').select('id,name')),
        readWorkspaceRows(
          widget.client.from('sites').select('id,agency_id,name'),
        ),
      ]);
      if (!mounted) return;
      final saved = await showModalBottomSheet<bool>(
        context: context,
        enableDrag: false,
        isScrollControlled: true,
        useSafeArea: true,
        constraints: const BoxConstraints(maxWidth: 620),
        builder: (_) => SupervisorAccessSheet(
          client: widget.client,
          user: user,
          assignments: _users
              .where((r) => r['user_id'] == user['user_id'])
              .toList(),
          agencies: data[0],
          sites: data[1],
        ),
      );
      if (saved == true && mounted) await _load();
    } catch (error) {
      if (mounted) setState(() => _error = functionMessage(error));
    }
  }

  Future<void> _editPersonnel(Map<String, dynamic> user) async {
    final saved = await showModalBottomSheet<bool>(
      context: context,
      enableDrag: false,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => WorkForm(
        sheet: true,
        title: 'Edit Personnel',
        fields: [
          WorkField(
            'full_name',
            'Full name',
            value: user['full_name'] as String,
          ),
          const WorkField(
            'password',
            'Confirm your account password',
            secret: true,
          ),
        ],
        save: (data) async {
          final response = await invokeProtected(
            widget.client,
            'manage-users',
            body: {
              ...data,
              'action': 'edit_personnel',
              'agency_id': user['agency_id'] ?? widget.agencyId,
              'user_id': user['user_id'],
            },
          );
          if (response.data is! Map || response.data['updated'] != true) {
            throw const FormatException('No edit confirmation received.');
          }
        },
      ),
    );
    if (saved == true && mounted) await _load();
  }

  Future<void> _assignPersonnel(Map<String, dynamic> user) async {
    if (!widget.access.isAdmin) return;
    try {
      final data = await Future.wait([
        readWorkspaceRows(widget.client.from('agencies').select('id,name')),
        readWorkspaceRows(
          widget.client.from('sites').select('id,agency_id,name'),
        ),
      ]);
      if (!mounted) return;
      if (data[0].isEmpty || data[1].isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Add a manpower company and workplace before assigning access.',
            ),
          ),
        );
        return;
      }
      final saved = await showModalBottomSheet<bool>(
        context: context,
        enableDrag: false,
        isScrollControlled: true,
        useSafeArea: true,
        builder: (_) => WorkForm(
          sheet: true,
          title: 'Assign Personnel workplace',
          fields: [
            WorkField(
              'agency_id',
              'Manpower company',
              choices: {
                for (final a in data[0]) a['id'] as String: a['name'] as String,
              },
            ),
            WorkField(
              'site_id',
              'Workplace',
              choicesFor: (values) => {
                for (final s in data[1].where(
                  (s) => s['agency_id'] == values['agency_id'],
                ))
                  s['id'] as String: s['name'] as String,
              },
            ),
            const WorkField(
              'password',
              'Confirm your account password',
              secret: true,
            ),
          ],
          save: (values) async {
            final response = await invokeProtected(
              widget.client,
              'manage-users',
              body: {
                ...values,
                'action': 'assign_personnel',
                'user_id': user['user_id'],
              },
            );
            if (response.data is! Map || response.data['updated'] != true) {
              throw const FormatException(
                'No assignment confirmation received.',
              );
            }
          },
        ),
      );
      if (saved == true && mounted) await _load();
    } catch (error) {
      if (mounted) setState(() => _error = functionMessage(error));
    }
  }

  Future<void> _change(Map<String, dynamic> user) async {
    final active = user['is_active'] == true;
    final changed = await showModalBottomSheet<bool>(
      context: context,
      enableDrag: false,
      isScrollControlled: true,
      useSafeArea: true,
      constraints: const BoxConstraints(maxWidth: 620),
      builder: (_) => WorkForm(
        sheet: true,
        title: active ? 'Suspend access' : 'Reactivate access',
        button: active ? 'Suspend' : 'Reactivate',
        description: 'Change workplace access for ${user['full_name']}.',
        fields: const [
          WorkField('password', 'Confirm your account password', secret: true),
        ],
        save: (data) async {
          await invokeProtected(
            widget.client,
            'manage-users',
            body: {
              ...data,
              'action': 'set_active',
              'agency_id': user['agency_id'] ?? widget.agencyId,
              'site_id': user['site_id'],
              'user_id': user['user_id'],
              'is_active': !active,
            },
          );
        },
      ),
    );
    if (changed != true || !mounted) return;
    setState(
      () => _notice = active
          ? 'Personnel access suspended for this workplace.'
          : 'Personnel access restored for this workplace.',
    );
    await _load();
  }

  Future<void> _usernameAccount(Map<String, dynamic> person) async {
    final saved = await manageUsernameAccount(
      context,
      client: widget.client,
      access: widget.access,
      agencyId: person['agency_id'] as String? ?? widget.agencyId,
      person: person,
    );
    if (saved && mounted) await _load();
  }

  Future<void> _deleteAccount(Map<String, dynamic> person) async {
    final name = person['full_name'] as String? ?? 'this person';
    final identifier =
        person['username'] ?? person['email'] ?? person['user_id'];
    final deleted = await showModalBottomSheet<bool>(
      context: context,
      enableDrag: false,
      isScrollControlled: true,
      useSafeArea: true,
      constraints: const BoxConstraints(maxWidth: 620),
      builder: (_) => WorkForm(
        sheet: true,
        title: 'Permanently delete $name?',
        button: 'Delete account permanently',
        description: 'Permanently removes sign-in access and PINs. Historical tasks, approvals and audit records are retained. This cannot be undone.',
        fields: [
          WorkField(
            'confirmation',
            'Type DELETE to erase $identifier',
            validate: (value) => value == 'DELETE'
                ? null
                : 'Type DELETE to confirm permanent deletion.',
          ),
          const WorkField(
            'password',
            'Confirm your account password',
            secret: true,
          ),
        ],
        save: (data) async {
          final result = await invokeProtected(
            widget.client,
            'manage-users',
            body: {
              ...data,
              'action': 'delete_account',
              'agency_id': person['agency_id'] ?? widget.agencyId,
              'user_id': person['user_id'],
            },
          );
          if (result.data is! Map || result.data['deleted'] != true) {
            throw const FormatException(
              'Refresh the team to check whether deletion completed.',
            );
          }
        },
      ),
    );
    if (deleted == true && mounted) {
      setState(() => _notice = 'Account deleted. Historical records retained.');
      await _load();
    }
  }

  String _siteName(Object? id) {
    for (final site in widget.sites) {
      if (site['id'] == id) return site['name'] as String;
    }
    return 'Workplace unavailable';
  }

  Future<void> _transfer(Map<String, dynamic> user) async {
    try {
      final agencies =
          (await readWorkspaceRows(
                widget.client.from('agencies').select('id,name'),
              ))
              .where(
                (a) =>
                    a['id'] != (user['agency_id'] ?? widget.agencyId) &&
                    widget.access.managesAgency(a['id'] as String),
              )
              .toList();
      final sites = await readWorkspaceRows(
        widget.client.from('sites').select('id,name,agency_id'),
      );
      if (!mounted) return;
      if (agencies.isEmpty) {
        setState(
          () => _notice = 'Add or obtain Supervisor access to the destination agency first, then create its workplace.',
        );
        return;
      }
      final saved = await showModalBottomSheet<bool>(
        context: context,
        enableDrag: false,
        isScrollControlled: true,
        useSafeArea: true,
        constraints: const BoxConstraints(maxWidth: 620),
        builder: (_) => WorkForm(
          sheet: true,
          title: 'Change Personnel Agency',
          button: 'Transfer',
          fields: [
            WorkField(
              'destination_agency_id',
              'New manpower agency',
              choices: {
                for (final a in agencies)
                  a['id'] as String: a['name'] as String,
              },
            ),
            WorkField(
              'destination_site_id',
              'New workplace',
              choicesFor: (values) => {
                for (final s in sites.where(
                  (s) => s['agency_id'] == values['destination_agency_id'],
                ))
                  s['id'] as String: s['name'] as String,
              },
            ),
            const WorkField('reason', 'Reason for transfer', lines: 3),
            const WorkField(
              'password',
              'Confirm your account password',
              secret: true,
            ),
          ],
          save: (data) async {
            final response = await invokeProtected(
              widget.client,
              'manage-users',
              body: {
                ...data,
                'action': 'transfer',
                'agency_id': user['agency_id'] ?? widget.agencyId,
                'user_id': user['user_id'],
              },
            );
            if (response.data is! Map || response.data['transferred'] != true) {
              throw const FormatException('No transfer confirmation received.');
            }
          },
        ),
      );
      if (saved == true && mounted) {
        setState(
          () => _notice =
              'Agency changed. Past work remains in its original agency.',
        );
        await _load();
      }
    } catch (error) {
      if (mounted) setState(() => _error = functionMessage(error));
    }
  }

  Future<void> _showPersonActions(
    Map<String, dynamic> user, {
    required bool canChange,
    required bool canDelete,
    required bool active,
    required String name,
    required Object? site,
  }) async {
    final unassignedPersonnel =
        widget.access.isAdmin &&
        user['is_unassigned'] == true &&
        user['role'] == 'personnel';
    final action = await showModalBottomSheet<String>(
      context: context,
      useSafeArea: true,
      constraints: const BoxConstraints(maxWidth: 620),
      builder: (sheetContext) => SafeArea(
        top: false,
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(sheetContext).height * 0.85,
          ),
          child: SingleChildScrollView(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 18),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 36,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Theme.of(sheetContext).colorScheme.outlineVariant,
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                  if (widget.access.isAdmin && user['role'] == 'supervisor')
                    ListTile(
                      leading: const Icon(Icons.admin_panel_settings_outlined),
                      title: const Text('Edit Supervisor access'),
                      onTap: () =>
                          Navigator.pop(sheetContext, 'supervisor_access'),
                    ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(12, 16, 12, 8),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        name,
                        style: Theme.of(sheetContext).textTheme.titleLarge,
                      ),
                    ),
                  ),
                  if (unassignedPersonnel)
                    ListTile(
                      leading: const Icon(Icons.add_business_outlined),
                      title: const Text('Assign workplace'),
                      onTap: () =>
                          Navigator.pop(sheetContext, 'assign_personnel'),
                    ),
                  if ((canChange || unassignedPersonnel) &&
                      user['account_status'] != 'suspended')
                    ListTile(
                      leading: const Icon(Icons.key_outlined),
                      title: const Text('Setup / recovery code'),
                      onTap: () => Navigator.pop(sheetContext, 'account_code'),
                    ),
                  if (canChange || unassignedPersonnel)
                    ListTile(
                      leading: const Icon(Icons.edit_outlined),
                      title: const Text('Edit Personnel'),
                      onTap: () =>
                          Navigator.pop(sheetContext, 'edit_personnel'),
                    ),
                  if (canChange)
                    ListTile(
                      leading: Icon(
                        active
                            ? Icons.person_off_outlined
                            : Icons.person_add_alt_outlined,
                      ),
                      title: Text(
                        active ? 'Suspend access' : 'Reactivate access',
                      ),
                      onTap: () => Navigator.pop(sheetContext, 'access'),
                    ),
                  if (canChange && active)
                    ListTile(
                      leading: const Icon(Icons.password_outlined),
                      title: const Text('Manage PIN'),
                      onTap: () => Navigator.pop(sheetContext, 'pin'),
                    ),
                  if (canChange &&
                      active &&
                      widget.agencyId != null &&
                      widget.access.managesAgency(widget.agencyId!))
                    ListTile(
                      leading: const Icon(Icons.swap_horiz_outlined),
                      title: const Text('Change agency'),
                      onTap: () => Navigator.pop(sheetContext, 'transfer'),
                    ),
                  if (canDelete) ...[
                    const Divider(),
                    ListTile(
                      leading: Icon(
                        Icons.delete_forever_outlined,
                        color: Theme.of(sheetContext).colorScheme.error,
                      ),
                      title: Text(
                        'Delete account permanently',
                        style: TextStyle(
                          color: Theme.of(sheetContext).colorScheme.error,
                        ),
                      ),
                      onTap: () =>
                          Navigator.pop(sheetContext, 'delete_account'),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
    if (!mounted) return;
    switch (action) {
      case 'edit_personnel':
        await _editPersonnel(user);
      case 'assign_personnel':
        await _assignPersonnel(user);
      case 'supervisor_access':
        await _editSupervisor(user);
      case 'access':
        await _change(user);
      case 'pin':
        await Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => PinManagementPage(
              client: widget.client,
              kind: 'employee',
              userId: user['user_id'] as String,
              fullName: name,
              agencyId: (user['agency_id'] as String? ?? widget.agencyId)!,
              siteId: site as String?,
            ),
          ),
        );
      case 'transfer':
        await _transfer(user);
      case 'account_code':
        await _usernameAccount(user);
      case 'delete_account':
        await _deleteAccount(user);
    }
  }

  @override
  Widget build(BuildContext context) {
    final directory =
        !widget.access.isAdmin && widget.access.isCompanyWideSupervisor;
    final mayInvite =
        widget.access.isAdmin ||
        (widget.agencyId != null &&
            widget.access.managesAgency(widget.agencyId!)) ||
        widget.sites.any(widget.access.managesSite);
    final activeCount = _users
        .where((u) => u['is_active'] == true && u['is_transferred'] != true)
        .length;
    return Scaffold(
      appBar: widget.embedded
          ? null
          : AppBar(
              title: Text(
                widget.supervisorManagement
                    ? 'Supervisor Management'
                    : 'People',
              ),
              actions: [
                IconButton(
                  tooltip: 'Refresh people',
                  onPressed: _loading ? null : _load,
                  icon: const Icon(Icons.refresh),
                ),
              ],
            ),
      floatingActionButton: mayInvite && !_loading && !widget.embedded
          ? FloatingActionButton.extended(
              onPressed: _invite,
              icon: const Icon(Icons.person_add_alt_1_outlined),
              label: const Text('Add person'),
            )
          : null,
      body: SafeArea(
        child: _loading
            ? const Center(
                child: CircularProgressIndicator(
                  semanticsLabel: 'Loading people',
                ),
              )
            : RefreshIndicator(
                onRefresh: _load,
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(18, 8, 18, 96),
                  children: [
                    if (widget.embedded)
                      Align(
                        alignment: Alignment.centerRight,
                        child: IconButton(
                          tooltip: 'Refresh people',
                          onPressed: _load,
                          icon: const Icon(Icons.refresh),
                        ),
                      ),
                    Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                widget.access.isAdmin || directory
                                    ? 'All agency assignments'
                                    : widget.agencyName,
                                style: Theme.of(context).textTheme.titleLarge,
                              ),
                              const SizedBox(height: 4),
                              Text(
                                '$activeCount active · ${_users.length} assignments',
                                style: TextStyle(
                                  color: Theme.of(context)
                                      .colorScheme
                                      .onSurfaceVariant,
                                ),
                              ),
                            ],
                          ),
                        ),
                        if (widget.embedded && mayInvite)
                          FilledButton.tonalIcon(
                            onPressed: _invite,
                            icon: const Icon(
                              Icons.person_add_alt_1_outlined,
                              size: 18,
                            ),
                            label: const Text('Add'),
                          ),
                      ],
                    ),
                    if (widget.access.isAdmin && !widget.supervisorManagement)
                      Align(
                        alignment: Alignment.centerLeft,
                        child: TextButton.icon(
                          icon: const Icon(Icons.admin_panel_settings_outlined),
                          label: const Text('Supervisor Management'),
                          onPressed: () => Navigator.push(
                            context,
                            MaterialPageRoute<void>(
                              builder: (_) => PeoplePage(
                                client: widget.client,
                                access: widget.access,
                                agencyId: widget.agencyId,
                                agencyName: widget.agencyName,
                                sites: widget.sites,
                                supervisorManagement: true,
                              ),
                            ),
                          ),
                        ),
                      ),
                    if (_notice != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 12),
                        child: Semantics(
                          liveRegion: true,
                          child: Card(
                            child: ListTile(
                              leading: const Icon(Icons.info_outline),
                              title: Text(_notice!),
                              trailing: IconButton(
                                tooltip: 'Dismiss',
                                onPressed: () => setState(() => _notice = null),
                                icon: const Icon(Icons.close),
                              ),
                            ),
                          ),
                        ),
                      ),
                    if (_error != null) ...[
                      const SizedBox(height: 12),
                      Semantics(liveRegion: true, child: Text(_error!)),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: TextButton.icon(
                          onPressed: _load,
                          icon: const Icon(Icons.refresh),
                          label: const Text('Retry'),
                        ),
                      ),
                    ] else if (_users.isEmpty) ...[
                      const SizedBox(height: 24),
                      const JanitraEmptyState(
                        'No team members yet.',
                        icon: Icons.people_outline,
                      ),
                    ] else ...[
                      const SizedBox(height: 18),
                      ..._users.map((user) {
                        final personnel = user['role'] == 'personnel';
                        final site = user['site_id'];
                        final canChange =
                            personnel &&
                            user['is_transferred'] != true &&
                            site is String &&
                            widget.access.managesSite({
                              'agency_id': user['agency_id'] ?? widget.agencyId,
                              'id': site,
                            });
                        final active = user['is_active'] == true;
                        final unassigned = user['is_unassigned'] == true;
                        final canDelete =
                            _historySafeDeletion &&
                            user['can_delete'] == true &&
                            (widget.access.isAdmin ||
                                (personnel &&
                                    site is String &&
                                    widget.access.managesSite({
                                      'agency_id':
                                          user['agency_id'] ?? widget.agencyId,
                                      'id': site,
                                    })));
                        final name =
                            user['full_name'] as String? ?? 'Unnamed person';
                        final email = user['email'] as String? ?? '';
                        return Card(
                          child: Padding(
                            padding: const EdgeInsets.symmetric(vertical: 5),
                            child: Column(
                              children: [
                                ListTile(
                                  leading: InitialsAvatar(name),
                                  title: Text(
                                    name,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                  subtitle: Text(
                                    [
                                      if (user['agency_name'] is String)
                                        user['agency_name'] as String,
                                      unassigned
                                          ? '${personnel ? 'Personnel' : 'Supervisor'} · Workplace not assigned'
                                          : personnel
                                          ? (user['site_name'] as String? ??
                                                _siteName(site))
                                          : 'Supervisor${site == null ? ' (company-wide)' : ' · ${user['site_name'] ?? _siteName(site)}'}',
                                    ].join(' · '),
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  trailing:
                                      canChange ||
                                          canDelete ||
                                          (widget.access.isAdmin && !personnel)
                                      ? IconButton(
                                          tooltip: 'Manage $name',
                                          icon: const Icon(Icons.more_vert),
                                          onPressed: () => _showPersonActions(
                                            user,
                                            canChange: canChange,
                                            canDelete: canDelete,
                                            active: active,
                                            name: name,
                                            site: site,
                                          ),
                                        )
                                      : null,
                                ),
                                Padding(
                                  padding: const EdgeInsets.fromLTRB(
                                    70,
                                    0,
                                    12,
                                    8,
                                  ),
                                  child: Row(
                                    children: [
                                      Expanded(
                                        child: Text(
                                          user['username'] is String
                                              ? 'Username: ${user['username']}'
                                              : email.isEmpty
                                              ? (personnel
                                                    ? 'Personnel'
                                                    : 'Supervisor')
                                              : email,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: TextStyle(
                                            color: Theme.of(context)
                                                .colorScheme
                                                .onSurfaceVariant,
                                            fontSize: 12,
                                          ),
                                        ),
                                      ),
                                      Flexible(
                                        child: WorkStatusBadge(
                                          alignment: Alignment.centerRight,
                                          status: unassigned
                                              ? 'PENDING'
                                              : active
                                              ? 'Active'
                                              : 'Suspended',
                                          label: unassigned
                                              ? 'Unassigned'
                                              : user['account_status'] ==
                                                    'setup_pending'
                                              ? 'Setup pending'
                                              : user['account_status'] ==
                                                    'recovery_pending'
                                              ? 'Recovery pending'
                                              : user['is_transferred'] == true
                                              ? 'Transferred'
                                              : active
                                              ? 'Active'
                                              : 'Suspended',
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      }),
                    ],
                  ],
                ),
              ),
      ),
    );
  }
}

class _InviteDialog extends StatefulWidget {
  const _InviteDialog({
    required this.client,
    required this.agencyId,
    required this.allowSupervisor,
    required this.sites,
    this.supervisorOnly = false,
  });
  final SupabaseClient client;
  final String? agencyId;
  final bool allowSupervisor;
  final bool supervisorOnly;
  final List<Map<String, dynamic>> sites;
  @override
  State<_InviteDialog> createState() => _InviteDialogState();
}

class _InviteDialogState extends State<_InviteDialog>
    with WidgetsBindingObserver {
  final _form = GlobalKey<FormState>();
  final _name = TextEditingController(),
      _username = TextEditingController(),
      _email = TextEditingController(),
      _password = TextEditingController();
  String _role = 'personnel';
  String _method = 'username';
  final _requestId = const Uuid().v4();
  bool get _usernameCreation => _role == 'personnel' && _method == 'username';
  String? _siteId, _error;
  bool _agencyWide = true;
  final _supervisorSites = <String>{};
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _siteId = widget.sites.length == 1
        ? widget.sites.single['id'] as String
        : null;
    if (widget.supervisorOnly ||
        (widget.sites.isEmpty && widget.allowSupervisor)) {
      _role = 'supervisor';
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _name.dispose();
    _username.dispose();
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) _password.clear();
  }

  Future<void> _save() async {
    if (_busy || !_form.currentState!.validate()) return;
    if (widget.agencyId != null &&
        _role == 'supervisor' &&
        !_agencyWide &&
        _supervisorSites.isEmpty) {
      setState(() => _error = 'Select at least one workplace.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final response = await invokeProtected(
        widget.client,
        'manage-users',
        body: {
          'action': _usernameCreation ? 'create_personnel' : 'invite',
          'agency_id': widget.agencyId,
          if (!_usernameCreation) 'role': _role,
          'site_id': _role == 'supervisor' ? null : _siteId,
          if (_role == 'supervisor')
            'site_ids': _agencyWide ? null : _supervisorSites.toList(),
          'full_name': _name.text.trim(),
          if (!_usernameCreation || _email.text.trim().isNotEmpty)
            'email': _email.text.trim(),
          if (_usernameCreation)
            'username': _username.text.trim().toLowerCase(),
          if (_usernameCreation) 'request_id': _requestId,
          'password': _password.text,
        },
      );
      if (_usernameCreation &&
          (response.data is! Map || response.data['setup_code'] is! String)) {
        throw const FormatException('No account setup confirmation received.');
      }
      if (mounted) {
        Navigator.pop(context, response.data as Map<String, dynamic>);
      }
    } catch (error) {
      if (mounted) setState(() => _error = functionMessage(error));
    } finally {
      if (mounted) {
        _password.clear();
        setState(() => _busy = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_busy,
    child: Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.87,
        ),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(22, 4, 22, 24),
          child: Form(
            key: _form,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(
                  child: Container(
                    width: 36,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.outlineVariant,
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                ),
                const SizedBox(height: 18),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Add team member',
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                    ),
                    IconButton(
                      tooltip: 'Close',
                      onPressed: _busy ? null : () => Navigator.pop(context),
                      icon: const Icon(Icons.close),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                TextFormField(
                  controller: _name,
                  enabled: !_busy,
                  maxLength: 200,
                  textCapitalization: TextCapitalization.words,
                  decoration: const InputDecoration(
                    counterText: '',
                    labelText: 'Full name',
                    prefixIcon: Icon(Icons.person_outline),
                  ),
                  validator: (value) => value == null || value.trim().isEmpty
                      ? 'Enter a name.'
                      : null,
                ),
                if (widget.allowSupervisor && !widget.supervisorOnly) ...[
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    initialValue: _role,
                    isExpanded: true,
                    decoration: const InputDecoration(labelText: 'Role'),
                    items: const [
                      DropdownMenuItem(
                        value: 'personnel',
                        child: Text('Personnel'),
                      ),
                      DropdownMenuItem(
                        value: 'supervisor',
                        child: Text('Supervisor'),
                      ),
                    ],
                    onChanged: _busy
                        ? null
                        : (value) => setState(() => _role = value!),
                  ),
                ],
                if (widget.agencyId == null) ...[
                  const SizedBox(height: 12),
                  const Text(
                    'This account will have no workplace access until Admin assigns a company and workplace.',
                  ),
                ],
                if (_role == 'supervisor' && widget.agencyId != null) ...[
                  const SizedBox(height: 12),
                  DropdownButtonFormField<bool>(
                    initialValue: _agencyWide,
                    isExpanded: true,
                    itemHeight: null,
                    decoration: const InputDecoration(
                      labelText: 'Supervisor access',
                    ),
                    items: const [
                      DropdownMenuItem(
                        value: true,
                        child: Text('Company-Wide'),
                      ),
                      DropdownMenuItem(
                        value: false,
                        child: Text('Site-Specific'),
                      ),
                    ],
                    onChanged: _busy
                        ? null
                        : (value) => setState(() => _agencyWide = value!),
                  ),
                  const Text(
                    'Company-Wide covers all manpower companies. Site-Specific covers selected workplaces.',
                  ),
                  if (!_agencyWide)
                    for (final site in widget.sites)
                      CheckboxListTile(
                        title: Text(site['name'] as String),
                        value: _supervisorSites.contains(site['id']),
                        onChanged: _busy
                            ? null
                            : (value) => setState(() {
                                if (value == true) {
                                  _supervisorSites.add(site['id'] as String);
                                } else {
                                  _supervisorSites.remove(site['id']);
                                }
                              }),
                      ),
                ],
                if (_role == 'personnel') ...[
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    key: const ValueKey('personnel-sign-in'),
                    initialValue: _method,
                    isExpanded: true,
                    itemHeight: null,
                    decoration: const InputDecoration(
                      labelText: 'Sign-in method',
                    ),
                    items: const [
                      DropdownMenuItem(
                        value: 'username',
                        child: Text('Username and password'),
                      ),
                      DropdownMenuItem(
                        value: 'email',
                        child: Text('Email invitation'),
                      ),
                    ],
                    onChanged: _busy
                        ? null
                        : (value) => setState(() => _method = value!),
                  ),
                ],
                if (_usernameCreation) ...[
                  const SizedBox(height: 12),
                  TextFormField(
                    key: const ValueKey('personnel-username'),
                    controller: _username,
                    enabled: !_busy,
                    autocorrect: false,
                    enableSuggestions: false,
                    decoration: const InputDecoration(
                      labelText: 'Unique username',
                    ),
                    validator: (value) =>
                        RegExp(r'^[a-zA-Z0-9][a-zA-Z0-9._-]{2,31}$')
                            .hasMatch((value ?? '').trim())
                        ? null
                        : 'Use 3–32 letters, digits, dots, hyphens or underscores.',
                  ),
                ],
                const SizedBox(height: 12),
                TextFormField(
                  key: const ValueKey('personnel-email'),
                  controller: _email,
                  enabled: !_busy,
                  keyboardType: TextInputType.emailAddress,
                  autofillHints: const [AutofillHints.email],
                  decoration: InputDecoration(
                    labelText: _usernameCreation
                        ? 'Contact email (optional)'
                        : 'Email address',
                    prefixIcon: const Icon(Icons.mail_outline),
                  ),
                  validator: (value) {
                    final email = (value ?? '').trim();
                    if (_usernameCreation && email.isEmpty) return null;
                    return RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$')
                                .hasMatch(email) &&
                            email.length <= 320
                        ? null
                        : 'Enter a valid email.';
                  },
                ),
                if (_role == 'personnel' && widget.agencyId != null) ...[
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    key: ValueKey(_siteId),
                    initialValue: _siteId,
                    isExpanded: true,
                    itemHeight: null,
                    decoration: const InputDecoration(labelText: 'Workplace'),
                    items: widget.sites
                        .map(
                          (site) => DropdownMenuItem(
                            value: site['id'] as String,
                            child: Text(
                              site['name'] as String,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        )
                        .toList(),
                    onChanged: _busy
                        ? null
                        : (value) => setState(() => _siteId = value),
                    validator: (value) =>
                        value == null ? 'Choose a workplace.' : null,
                  ),
                ],
                const SizedBox(height: 12),
                SecretTextFormField(
                  controller: _password,
                  enabled: !_busy,
                  autofillHints: const [AutofillHints.password],
                  decoration: const InputDecoration(
                    labelText: 'Your account password',
                    prefixIcon: Icon(Icons.lock_outline),
                  ),
                  validator: (value) => value == null || value.isEmpty
                      ? 'Enter your password.'
                      : null,
                ),
                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 10),
                    child: Semantics(
                      liveRegion: true,
                      child: Text(
                        _error!,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                    ),
                  ),
                const SizedBox(height: 18),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: _busy ? null : () => Navigator.pop(context),
                        child: const Text('Cancel'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: FilledButton(
                        onPressed: _busy ? null : _save,
                        child: Text(
                          _busy
                              ? 'Saving…'
                              : _usernameCreation
                              ? 'Create account'
                              : 'Send invite',
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}
