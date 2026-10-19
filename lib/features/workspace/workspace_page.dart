import 'package:flutter/material.dart';

import '../appearance/appearance_page.dart';
import '../about/about_page.dart';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/access_notice.dart';
import '../../core/access_policy.dart';
import '../../core/account_label.dart';
import '../../core/app_theme.dart';
import '../work/work_form.dart';
import '../work/work_overview.dart';
import '../work/task_page.dart';
import '../work/scheduling_page.dart';
import '../work/records_page.dart';
import '../work/offline_work_page.dart';
import '../work/personal_schedule_page.dart';
import '../work/work_repository.dart';
import '../reports/reports_page.dart';

import 'name_editor.dart';
import 'people_page.dart';
import 'pin_management_page.dart';
import '../authentication/mfa_page.dart';
import 'workspace_access.dart';

class WorkspacePage extends StatefulWidget {
  const WorkspacePage({
    super.key,
    required this.client,
    required this.access,
    required this.onRefreshAccess,
  });
  final SupabaseClient client;
  final WorkspaceAccess access;
  final VoidCallback onRefreshAccess;

  @override
  State<WorkspacePage> createState() => _WorkspacePageState();
}

class _WorkspacePageState extends State<WorkspacePage> {
  List<Map<String, dynamic>> _agencies = [], _clients = [], _sites = [];
  String? _agencyId, _error;
  late String _fullName = widget.access.fullName;
  bool _loading = true, _signingOut = false;
  int _tab = 0, _loadVersion = 0;
  final _visited = <int>{0};
  void _select(int tab) => setState(() {
    _tab = tab;
    _visited.add(tab);
  });

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load([String? agencyId]) async {
    final version = ++_loadVersion;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final agencies = await readWorkspaceRows(
        widget.client.from('agencies').select('id,name'),
      );
      agencies.sort(
        (a, b) => (a['name'] as String).compareTo(b['name'] as String),
      );
      final wanted =
          agencyId ??
          _agencyId ??
          widget.access.roles
              .map((r) => r['agency_id'])
              .whereType<String>()
              .firstOrNull;
      final selected = agencies.any((a) => a['id'] == wanted)
          ? wanted
          : agencies.isEmpty
          ? null
          : agencies.first['id'] as String;
      final data = selected == null
          ? [<Map<String, dynamic>>[], <Map<String, dynamic>>[]]
          : await Future.wait([
              readWorkspaceRows(
                widget.client
                    .from('client_companies')
                    .select('id,agency_id,name')
                    .eq('agency_id', selected),
              ),
              readWorkspaceRows(
                widget.client
                    .from('sites')
                    .select('id,agency_id,client_company_id,name')
                    .eq('agency_id', selected),
              ),
            ]);
      for (final rows in data) {
        rows.sort(
          (a, b) => (a['name'] as String).compareTo(b['name'] as String),
        );
      }
      if (mounted && version == _loadVersion) {
        setState(() {
          _agencies = agencies;
          _agencyId = selected;
          _clients = data[0];
          _sites = data[1];
        });
      }
    } catch (_) {
      if (mounted && version == _loadVersion) {
        setState(
          () => _error =
              'Could not load workplaces. Check your connection and try again.',
        );
      }
    } finally {
      if (mounted && version == _loadVersion) setState(() => _loading = false);
    }
  }

  Future<void> _signOut() async {
    if (_signingOut) return;
    setState(() => _signingOut = true);
    try {
      await widget.client.auth.signOut();
    } catch (_) {
      if (mounted) {
        setState(
          () => _error =
              'Could not sign out. Check your connection and try again.',
        );
      }
    } finally {
      if (mounted) setState(() => _signingOut = false);
    }
  }

  Future<void> _edit({
    required String title,
    required String label,
    String initialName = '',
    List<Map<String, dynamic>>? clients,
    String? contextLabel,
    required Future<void> Function(String, String?) save,
  }) async {
    final saved = await showModalBottomSheet<bool>(
      context: context,
      enableDrag: false,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: false,
      builder: (_) => NameEditor(
        title: title,
        label: label,
        initialName: initialName,
        clients: clients,
        contextLabel: contextLabel,
        onSave: (name, clientId) async {
          AccessPolicy.of(widget.client).requireVerified();
          await save(name, clientId);
        },
      ),
    );
    if (saved == true && mounted) await _load();
  }

  Future<void> _addClient() async {
    final agency = _agencyId;
    if (agency == null || !widget.access.managesAgency(agency)) return;
    await _edit(
      title: 'Add Client Company',
      label: 'Client company name',
      save: (name, _) async {
        await widget.client
            .from('client_companies')
            .insert({'agency_id': agency, 'name': name})
            .select('id')
            .single();
      },
    );
  }

  Future<void> _addSite() async {
    final agency = _agencyId;
    if (agency == null ||
        !widget.access.managesAgency(agency) ||
        _clients.isEmpty) {
      return;
    }
    await _edit(
      title: 'Add Workplace',
      label: 'Workplace name',
      clients: _clients,
      save: (name, clientId) async {
        if (!_clients.any((c) => c['id'] == clientId)) {
          throw const FormatException('Invalid client');
        }
        await widget.client
            .from('sites')
            .insert({
              'agency_id': agency,
              'client_company_id': clientId,
              'name': name,
            })
            .select('id')
            .single();
      },
    );
  }

  Future<void> _rename(
    String table,
    Map<String, dynamic> row,
    String title,
    String label,
  ) async {
    final allowed = table == 'agencies'
        ? widget.access.managesAgency(row['id'] as String)
        : table == 'client_companies'
        ? widget.access.managesAgency(row['agency_id'] as String)
        : widget.access.managesSite(row);
    if (!allowed) return;
    await _edit(
      title: title,
      label: label,
      initialName: row['name'] as String,
      contextLabel: table == 'sites'
          ? 'Client company: ${_clients.where((c) => c['id'] == row['client_company_id']).map((c) => c['name']).firstOrNull ?? 'Unknown'}'
          : null,
      save: (name, _) async {
        await widget.client
            .from(table)
            .update({'name': name})
            .eq('id', row['id'])
            .select('id')
            .single();
      },
    );
  }

  Future<void> _editProfile() async {
    await _edit(
      title: 'Edit Your Name',
      label: 'Your full name',
      initialName: _fullName,
      save: (name, _) async {
        await widget.client
            .from('profiles')
            .update({'full_name': name})
            .eq('id', widget.client.auth.currentUser!.id)
            .select('id')
            .single();
        if (mounted) setState(() => _fullName = name);
      },
    );
  }

  Widget _heading(String value) => Padding(
    padding: const EdgeInsets.only(top: 24, bottom: 12),
    child: Text(
      value,
      style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
    ),
  );

  Widget _siteList() => Column(
    children: _sites.map((site) {
      final client = _clients
          .where((c) => c['id'] == site['client_company_id'])
          .firstOrNull;
      return Card(
        child: ListTile(
          leading: const Icon(Icons.location_on_outlined),
          title: Text(
            site['name'] as String,
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
          subtitle: Text(client?['name'] as String? ?? 'No client company'),
          trailing: widget.access.managesSite(site)
              ? IconButton(
                  tooltip: 'Edit workplace ${site['name']}',
                  icon: const Icon(Icons.edit_outlined, size: 20),
                  onPressed: () => _rename(
                    'sites',
                    site,
                    'Edit Workplace',
                    'Workplace name',
                  ),
                )
              : null,
        ),
      );
    }).toList(),
  );

  Widget _home() {
    final supervisor =
        _agencyId != null && widget.access.supervisesAgency(_agencyId!);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        WorkOverview(
          key: ValueKey(_agencyId),
          client: widget.client,
          access: widget.access,
          agencyId: _agencyId,
        ),
        if (supervisor && _sites.isEmpty) ...[
          _heading('Your workplaces'),
          LayoutBuilder(
            builder: (context, constraints) {
              Widget count(String label, int value) => Card(
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '$value',
                        style: const TextStyle(
                          fontSize: 28,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(label, style: const TextStyle(fontSize: 16)),
                    ],
                  ),
                ),
              );
              final cards = [
                count('Client companies', _clients.length),
                count('Workplaces', _sites.length),
              ];
              return constraints.maxWidth >= 360 &&
                      MediaQuery.textScalerOf(context).scale(16) <= 20
                  ? Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: cards
                          .map((card) => Expanded(child: card))
                          .toList(),
                    )
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: cards,
                    );
            },
          ),
          const SizedBox(height: 24),
          Text(
            _sites.isEmpty
                ? 'Add a client company, then add its workplace to begin setting up your team.'
                : 'Manage your client companies and workplaces from the Workplaces tab.',
            style: const TextStyle(fontSize: 16),
          ),
        ] else if (!supervisor && _sites.isEmpty) ...[
          _heading('Assigned workplaces'),
          if (_sites.isEmpty)
            const Text(
              'No workplace is assigned. Please contact your supervisor.',
            )
          else
            _siteList(),
        ],
      ],
    );
  }

  Future<void> _openPeople() async {
    final id = _agencyId;
    if (!widget.access.isAdmin &&
        (id == null || !widget.access.supervisesAgency(id))) {
      return;
    }
    final name = id == null
        ? 'Unassigned people'
        : _agencies.firstWhere((agency) => agency['id'] == id)['name']
              as String;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => PeoplePage(
          client: widget.client,
          access: widget.access,
          agencyId: id,
          agencyName: name,
          sites: _sites,
        ),
      ),
    );
  }

  Widget _workplaces() {
    final canManage =
        _agencyId != null && widget.access.managesAgency(_agencyId!);
    final canSupervise =
        _agencyId != null && widget.access.supervisesAgency(_agencyId!);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionHeading(
          'Client companies',
          count: _clients.length,
          action: canManage ? 'Add' : null,
          actionTooltip: 'Add Client Company',
          onAction: _addClient,
        ),
        if (_clients.isEmpty)
          const JanitraEmptyState(
            'No client companies yet.',
            icon: Icons.apartment_outlined,
          )
        else
          ..._clients.map(
            (client) => Card(
              child: ListTile(
                leading: const Icon(Icons.apartment_outlined),
                title: Text(client['name'] as String),
                trailing: canManage
                    ? IconButton(
                        tooltip: 'Edit client ${client['name']}',
                        icon: const Icon(Icons.edit_outlined, size: 20),
                        onPressed: () => _rename(
                          'client_companies',
                          client,
                          'Edit Client Company',
                          'Client company name',
                        ),
                      )
                    : null,
              ),
            ),
          ),
        SectionHeading(
          'Workplaces',
          count: _sites.length,
          action: canManage ? 'Add' : null,
          actionTooltip: 'Add Workplace',
          onAction: canManage && _clients.isNotEmpty ? _addSite : null,
        ),
        if (_sites.isEmpty)
          JanitraEmptyState(
            _clients.isEmpty
                ? 'Add a client company first.'
                : 'No workplaces yet.',
            icon: Icons.location_on_outlined,
          )
        else
          _siteList(),
        if (canSupervise) ...[
          const SectionHeading('Management'),
          Card(
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.groups_outlined),
                  title: const Text('People'),
                  subtitle: const Text('Team members and access'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: _openPeople,
                ),
                const Divider(height: 1, indent: 56),
                ListTile(
                  leading: const Icon(Icons.calendar_month_outlined),
                  title: const Text('Schedules & activities'),
                  subtitle: const Text('Shifts, cleaning and deadlines'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => _open(
                    SchedulingPage(
                      client: widget.client,
                      access: widget.access,
                      agencyId: _agencyId!,
                      sites: _sites,
                    ),
                  ),
                ),
                const Divider(height: 1, indent: 56),
                ListTile(
                  leading: const Icon(Icons.bar_chart_outlined),
                  title: const Text('Work reports'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => _open(
                    ReportsPage(
                      client: widget.client,
                      agencyId: _agencyId!,
                      agencyName:
                          _agencies.firstWhere(
                                (a) => a['id'] == _agencyId,
                              )['name']
                              as String,
                      sites: _sites,
                    ),
                  ),
                ),
                const Divider(height: 1, indent: 56),
                ListTile(
                  leading: const Icon(Icons.history_outlined),
                  title: const Text('Audit log'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => _open(
                    RecordsPage(
                      client: widget.client,
                      kind: 'Audit Log',
                      agencyId: _agencyId,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  Future<void> _openSupervisorPin() async {
    final role = widget.access.roles.firstWhere(
      (role) => role['role'] == 'supervisor' && role['agency_id'] == _agencyId,
      orElse: () => {'agency_id': _agencyId, 'site_id': null},
    );
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => PinManagementPage(
          client: widget.client,
          kind: 'supervisor',
          userId: widget.client.auth.currentUser!.id,
          fullName: _fullName,
          agencyId: role['agency_id'] as String,
          siteId: role['site_id'] as String?,
        ),
      ),
    );
  }

  Future<void> _open(Widget page) =>
      Navigator.of(context).push<void>(MaterialPageRoute(builder: (_) => page));

  Future<void> _addAgency() async {
    if (!widget.access.isAdmin && !widget.access.isCompanyWideSupervisor) {
      return;
    }
    String? createdAgency;
    final saved = await showDialog<bool>(
      context: context,
      builder: (_) => WorkForm(
        title: 'Add Manpower Agency',
        fields: const [
          WorkField('name', 'Agency name'),
          WorkField('password', 'Confirm your account password', secret: true),
        ],
        save: (data) async {
          final response = await invokeProtected(
            widget.client,
            'manage-users',
            body: {...data, 'action': 'create_agency', 'agency_id': _agencyId},
          );
          if (response.data is! Map || response.data['agency_id'] is! String) {
            throw const FormatException('No agency confirmation received.');
          }
          createdAgency = response.data['agency_id'] as String;
        },
      ),
    );
    if (saved == true && mounted) await _load(createdAgency);
  }

  Widget _profile() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Card(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  InitialsAvatar(_fullName),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Text(
                      'Your account',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
              const Divider(),
              Text(
                _fullName,
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                accountLabel(widget.client.auth.currentUser),
                style: const TextStyle(fontSize: 16),
              ),
              TextButton.icon(
                onPressed: _editProfile,
                icon: const Icon(Icons.edit_outlined),
                label: const Text('Edit Your Name'),
              ),
            ],
          ),
        ),
      ),
      Card(
        child: Column(
          children: [
            ListTile(
              leading: const Icon(Icons.palette_outlined),
              title: const Text('Appearance'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => _open(const AppearancePage()),
            ),
            ListTile(
              leading: const Icon(Icons.info_outline),
              title: const Text('About JANITRA'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => _open(const AboutPage()),
            ),
            ListTile(
              leading: const Icon(Icons.shield_outlined),
              title: const Text('Two-Step Verification'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.of(context).push<void>(
                MaterialPageRoute(
                  builder: (_) => MfaPage(client: widget.client),
                ),
              ),
            ),
            if (_agencyId != null && widget.access.supervisesAgency(_agencyId!))
              ListTile(
                leading: const Icon(Icons.pin_outlined),
                onTap: _openSupervisorPin,
                title: const Text('Manage Your Supervisor PIN'),
                trailing: const Icon(Icons.chevron_right),
              ),
          ],
        ),
      ),
      Card(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _heading('Manpower companies'),
              if (!widget.access.isSupervisor)
                const Text(
                  'Your Supervisor manages your agency and workplace assignment.',
                ),
              ..._agencies.map(
                (agency) => ListTile(
                  leading: const Icon(Icons.business_outlined),
                  contentPadding: EdgeInsets.zero,
                  title: Text(
                    agency['name'] as String,
                    style: const TextStyle(fontSize: 16),
                  ),
                  trailing: widget.access.managesAgency(agency['id'] as String)
                      ? IconButton(
                          tooltip: 'Edit company ${agency['name']}',
                          icon: const Icon(Icons.edit_outlined),
                          onPressed: () => _rename(
                            'agencies',
                            agency,
                            'Edit Manpower Company',
                            'Manpower company name',
                          ),
                        )
                      : null,
                ),
              ),
              if (widget.access.isAdmin ||
                  widget.access.isCompanyWideSupervisor)
                TextButton.icon(
                  onPressed: _addAgency,
                  icon: const Icon(Icons.add_business_outlined),
                  label: const Text('Add Manpower Agency'),
                ),
              const SizedBox(height: 12),
            ],
          ),
        ),
      ),
      Card(
        child: Column(
          children: [
            ListTile(
              leading: const Icon(Icons.notifications_outlined),
              onTap: () => _open(
                RecordsPage(client: widget.client, kind: 'Notifications'),
              ),
              title: const Text('Notifications'),
              trailing: const Icon(Icons.chevron_right),
            ),
            ListTile(
              leading: const Icon(Icons.history_outlined),
              onTap: () => _open(
                RecordsPage(client: widget.client, kind: 'Agency History'),
              ),
              title: const Text('My Agency History'),
              trailing: const Icon(Icons.chevron_right),
            ),
            if (widget.access.roles.any((r) => r['role'] == 'personnel'))
              ListTile(
                leading: const Icon(Icons.offline_pin_outlined),
                onTap: () => _open(
                  OfflineWorkPage(
                    owner: widget.client.auth.currentUser!.id,
                    client: widget.client,
                  ),
                ),
                title: const Text('Saved Offline Work'),
                trailing: const Icon(Icons.chevron_right),
              ),
            if (widget.access.roles.any((r) => r['role'] == 'personnel'))
              ListTile(
                leading: const Icon(Icons.calendar_month_outlined),
                onTap: () => _open(
                  PersonalSchedulePage(repo: WorkRepository(widget.client)),
                ),
                title: const Text('My Work Schedule'),
                trailing: const Icon(Icons.chevron_right),
              ),
          ],
        ),
      ),
      const SizedBox(height: 24),
      TextButton.icon(
        onPressed: widget.onRefreshAccess,
        icon: const Icon(Icons.refresh),
        label: const Text('Refresh Workplace Access'),
      ),
      const SizedBox(height: 12),
      FilledButton.icon(
        onPressed: _signingOut ? null : _signOut,
        icon: const Icon(Icons.logout),
        label: Text(_signingOut ? 'Signing out…' : 'Sign Out'),
      ),
    ],
  );

  @override
  Widget build(BuildContext context) {
    final supervisor = widget.access.isSupervisor;
    final tabs = supervisor ? [0, 3, 4, 5] : [0, 3, 2];
    final selected = tabs.indexOf(_tab);
    return Scaffold(
      appBar: AppBar(
        toolbarHeight:
            (_tab == 0 ? 88 : 72) *
            (MediaQuery.textScalerOf(context).scale(16) / 32).clamp(
              1,
              double.infinity,
            ),
        title: _tab == 0
            ? Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Hello, $_fullName',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 5),
                  Text(
                    _sites.isEmpty
                        ? (supervisor
                              ? 'Supervisor workspace'
                              : 'Personnel workspace')
                        : _sites.map((s) => s['name']).join(' · '),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 14,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              )
            : Text(switch (_tab) {
                1 => 'Workplaces',
                2 => 'Profile',
                3 => supervisor ? 'Tasks' : 'My Tasks',
                4 => 'Team',
                _ => 'Reports',
              }),
        actions: [
          if (supervisor)
            IconButton(
              tooltip: 'Workplaces',
              onPressed: () => _select(1),
              icon: const Icon(Icons.business_outlined),
            ),
          IconButton(
            tooltip: 'Profile',
            onPressed: () => _select(2),
            icon: InitialsAvatar(_fullName),
          ),
          const SizedBox(width: 8),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        animationDuration:
            MediaQuery.disableAnimationsOf(context) ||
                FocusManager.instance.highlightMode ==
                    FocusHighlightMode.traditional
            ? Duration.zero
            : const Duration(milliseconds: 180),
        selectedIndex: selected < 0 ? 0 : selected,
        onDestinationSelected: (index) => _select(tabs[index]),
        destinations: [
          const NavigationDestination(
            icon: Icon(Icons.home_outlined),
            selectedIcon: Icon(Icons.home),
            label: 'Home',
          ),
          NavigationDestination(
            icon: Icon(Icons.checklist),
            label: supervisor ? 'Tasks' : 'My Tasks',
          ),
          if (supervisor) ...[
            const NavigationDestination(
              icon: Icon(Icons.people_outline),
              label: 'Team',
            ),
            const NavigationDestination(
              icon: Icon(Icons.assessment_outlined),
              label: 'Reports',
            ),
          ] else
            const NavigationDestination(
              icon: Icon(Icons.person_outline),
              selectedIcon: Icon(Icons.person),
              label: 'Profile',
            ),
        ],
      ),
      body: SafeArea(
        child: _loading
            ? const Center(
                child: CircularProgressIndicator(
                  semanticsLabel: 'Loading workplaces',
                ),
              )
            : _error != null
            ? SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: Column(
                  children: [
                    Semantics(
                      liveRegion: true,
                      child: Text(
                        _error!,
                        style: const TextStyle(fontSize: 16),
                      ),
                    ),
                    TextButton(
                      onPressed: () => _load(),
                      child: const Text('Retry'),
                    ),
                    TextButton(
                      onPressed: widget.onRefreshAccess,
                      child: const Text('Refresh Workplace Access'),
                    ),
                  ],
                ),
              )
            : Column(
                children: [
                  if (_agencies.length > 1)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
                      child: DropdownButtonFormField<String>(
                        key: ValueKey(_agencyId),
                        initialValue: _agencyId,
                        isExpanded: true,
                        itemHeight: null,
                        decoration: const InputDecoration(
                          labelText: 'Manpower company',
                        ),
                        items: _agencies
                            .map(
                              (agency) => DropdownMenuItem(
                                value: agency['id'] as String,
                                child: Text(agency['name'] as String),
                              ),
                            )
                            .toList(),
                        onChanged: (id) {
                          if (id != null && id != _agencyId) _load(id);
                        },
                      ),
                    )
                  else if (supervisor && _agencies.length == 1)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
                      child: InputDecorator(
                        key: const ValueKey('current-agency'),
                        decoration: const InputDecoration(
                          labelText: 'Manpower company',
                          prefixIcon: Icon(Icons.business_outlined),
                        ),
                        child: Tooltip(
                          message: _agencies.single['name'] as String,
                          child: Text(
                            _agencies.single['name'] as String,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ),
                    )
                  else if (_agencies.isEmpty)
                    const Text(
                      'No manpower company is available. Refresh your workplace access or contact your supervisor.',
                    ),
                  Expanded(
                    child: IndexedStack(
                      index: _tab,
                      children: List.generate(6, (index) {
                        if (!_visited.contains(index)) {
                          return const SizedBox.shrink();
                        }
                        if (index == 3) {
                          return TasksPage(
                            key: ValueKey('tasks/$_agencyId'),
                            client: widget.client,
                            access: widget.access,
                            agencyId: _agencyId,
                            embedded: true,
                          );
                        }
                        if ((index == 5 ||
                                (index == 4 && !widget.access.isAdmin)) &&
                            (_agencyId == null ||
                                !widget.access.supervisesAgency(_agencyId!))) {
                          return const Center(
                            child: Padding(
                              padding: EdgeInsets.all(24),
                              child: Text(
                                'Select an agency you supervise to manage its team and reports.',
                              ),
                            ),
                          );
                        }
                        if (index == 4 &&
                            (_agencyId != null || widget.access.isAdmin)) {
                          return PeoplePage(
                            key: ValueKey('people/$_agencyId'),
                            client: widget.client,
                            access: widget.access,
                            agencyId: _agencyId,
                            agencyName: _agencyId == null
                                ? 'Unassigned people'
                                : _agencies.firstWhere(
                                        (a) => a['id'] == _agencyId,
                                      )['name']
                                      as String,
                            sites: _sites,
                            embedded: true,
                          );
                        }
                        if (index == 5 && _agencyId != null) {
                          return ReportsPage(
                            key: ValueKey('reports/$_agencyId'),
                            client: widget.client,
                            agencyId: _agencyId!,
                            agencyName:
                                _agencies.firstWhere(
                                      (a) => a['id'] == _agencyId,
                                    )['name']
                                    as String,
                            sites: _sites,
                            embedded: true,
                          );
                        }
                        return SingleChildScrollView(
                          key: PageStorageKey('workspace/$index/$_agencyId'),
                          padding: const EdgeInsets.all(20),
                          child: index == 0
                              ? _home()
                              : index == 1
                              ? _workplaces()
                              : _profile(),
                        );
                      }),
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}
