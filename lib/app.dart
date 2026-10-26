import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'features/authentication/login_page.dart';
import 'features/authentication/company_setup_page.dart';
import 'features/authentication/reset_password_page.dart';
import 'features/authentication/mfa_page.dart';
import 'features/workspace/workspace_access.dart';
import 'features/workspace/workspace_page.dart';
import 'features/work/offline_work_page.dart';
import 'features/work/offline_access.dart';
import 'features/work/local_work_store.dart';
import 'features/work/personal_sync.dart';
import 'core/access_notice.dart';
import 'core/app_theme.dart';
import 'core/access_policy.dart';
import 'core/account_label.dart';
import 'core/appearance_settings.dart';
import 'core/startup_reveal.dart';
import 'features/updates/update_prompt.dart';
import 'features/privacy/privacy_policy_page.dart';

class JanitraApp extends StatefulWidget {
  const JanitraApp({super.key, this.client, this.appearance});
  final SupabaseClient? client;
  final AppearanceSettings? appearance;

  @override
  State<JanitraApp> createState() => _JanitraAppState();
}

class _JanitraAppState extends State<JanitraApp> {
  late final _appearance = widget.appearance ?? AppearanceSettings();
  final _navigatorKey = GlobalKey<NavigatorState>();

  @override
  void dispose() {
    if (widget.appearance == null) _appearance.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AppearanceScope(
    settings: _appearance,
    child: ListenableBuilder(
      listenable: _appearance,
      builder: (context, _) => MaterialApp(
        navigatorKey: _navigatorKey,
        title: 'JANITRA',
        debugShowCheckedModeBanner: false,
        themeMode: _appearance.mode,
        themeAnimationDuration:
            _appearance.motion == MotionPreference.on ||
                (_appearance.motion == MotionPreference.system &&
                    WidgetsBinding
                        .instance
                        .platformDispatcher
                        .accessibilityFeatures
                        .disableAnimations)
            ? Duration.zero
            : kThemeAnimationDuration,
        theme: janitraTheme(
          accent: _appearance.accent,
          font: _appearance.font,
          background: _appearance.backgroundFor(Brightness.light),
          foreground: _appearance.foregroundFor(Brightness.light),
          highContrast: _appearance.highContrast,
        ),
        darkTheme: janitraTheme(
          brightness: Brightness.dark,
          accent: _appearance.accent,
          font: _appearance.font,
          background: _appearance.backgroundFor(Brightness.dark),
          foreground: _appearance.foregroundFor(Brightness.dark),
          highContrast: _appearance.highContrast,
        ),
        builder: (context, child) {
          final media = MediaQuery.of(context);
          final reduced = switch (_appearance.motion) {
            MotionPreference.system => media.disableAnimations,
            MotionPreference.on => true,
            MotionPreference.off => false,
          };
          return MediaQuery(
            data: media.copyWith(
              textScaler: _appearance.textScale == 1
                  ? media.textScaler
                  : AppearanceTextScaler(
                      media.textScaler,
                      _appearance.textScale,
                    ),
              disableAnimations: reduced,
            ),
            child: UpdatePromptHost(
              navigatorKey: _navigatorKey,
              child: widget.client == null
                  ? child!
                  : ConnectivityShield(client: widget.client!, child: child!),
            ),
          );
        },
        home: StartupReveal(
          child: widget.client == null
              ? Scaffold(
                  body: SafeArea(
                    child: Center(
                      child: Padding(
                        padding: EdgeInsets.all(24),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Text(
                              'JANITRA could not connect. Please restart the app or contact your supervisor.',
                              textAlign: TextAlign.center,
                            ),
                            const SizedBox(height: 16),
                            TextButton.icon(
                              onPressed: () =>
                                  _navigatorKey.currentState?.push<void>(
                                    MaterialPageRoute(
                                      builder: (_) => const PrivacyPolicyPage(),
                                    ),
                                  ),
                              icon: const Icon(Icons.privacy_tip_outlined),
                              label: const Text('Privacy Policy'),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                )
              : _AuthGate(widget.client!),
        ),
      ),
    ),
  );
}

class _AuthGate extends StatefulWidget {
  const _AuthGate(this.client);
  final SupabaseClient client;

  @override
  State<_AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<_AuthGate> {
  bool _recovering = false;
  bool _hadSession = false;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<AuthState>(
      stream: widget.client.auth.onAuthStateChange,
      builder: (context, snapshot) {
        if (widget.client.auth.currentSession == null) {
          if (_hadSession) {
            _hadSession = false;
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) {
                Navigator.of(context).popUntil((route) => route.isFirst);
              }
            });
          }
          _recovering = false;
          return LoginPage(client: widget.client);
        }
        _hadSession = true;
        if (snapshot.data?.event == AuthChangeEvent.passwordRecovery) {
          if (!_recovering) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) {
                Navigator.of(context).popUntil((route) => route.isFirst);
              }
            });
          }
          _recovering = true;
        }
        return _AccountPendingPage(
          key: ValueKey('${widget.client.auth.currentUser!.id}/$_recovering'),
          client: widget.client,
          recovering: _recovering,
        );
      },
    );
  }
}

class _AccountPendingPage extends StatefulWidget {
  const _AccountPendingPage({
    super.key,
    required this.client,
    this.recovering = false,
  });
  final SupabaseClient client;
  final bool recovering;

  @override
  State<_AccountPendingPage> createState() => _AccountPendingPageState();
}

class _AccountPendingPageState extends State<_AccountPendingPage>
    with WidgetsBindingObserver {
  bool _busy = false;
  String? _error;
  bool _checking = true;
  bool _needsSetup = false;
  bool _needsPassword = false;
  List<Factor> _mfaFactors = [];
  bool _verifiedPersonal = false, _offlineAllowed = false;
  bool _offlineRevoked = false;
  late final String _ownerId;
  Future<void> _proofWrites = Future<void>.value();
  WorkspaceAccess? _access;
  int _loadVersion = 0;
  int? _runningVersion;
  Future<void>? _validation;
  bool _refreshQueued = false;
  Timer? _resumeTimer, _expiryTimer;
  Timer? _reconnectTimer;
  late final _policy = AccessPolicy.of(widget.client);
  StreamSubscription<AuthState>? _authSubscription;
  StreamSubscription<AccessNotice>? _accessSubscription;
  String? _sessionToken;
  String? _sessionUserId;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _ownerId = widget.client.auth.currentUser!.id;
    _policy.enforced = true;
    _policy.verified = false;
    _policy.retry = _checkSetup;
    _policy.signOut = _signOut;
    _policy.openCache = () async {
      if (!_policy.cacheAllowed) return;
      final session = widget.client.auth.currentSession;
      if (session == null || !await mayReadOfflinePersonalWork(session)) return;
      if (!mounted) return;
      _policy.showCache(true);
      try {
        await Navigator.of(context).push(
          MaterialPageRoute<void>(
            settings: const RouteSettings(name: 'offline-personal'),
            builder: (_) =>
                OfflineWorkPage(owner: _ownerId, client: widget.client),
          ),
        );
      } finally {
        _policy.showCache(false);
      }
    };
    _sessionToken = widget.client.auth.currentSession?.accessToken;
    _sessionUserId = widget.client.auth.currentUser?.id;
    _watchSessionExpiry();
    _accessSubscription = AccessNotice.events.listen((notice) {
      if (!identical(notice.client, widget.client) ||
          notice.userId != widget.client.auth.currentUser?.id) {
        return;
      }
      if (notice.token != widget.client.auth.currentSession?.accessToken) {
        if (notice.code != 'verification_unavailable') _checkSetup();
        return;
      }
      if (notice.code == 'verification_unavailable') {
        if (notice.token != widget.client.auth.currentSession?.accessToken) {
          return;
        }
        _degradeAccess(personalOffline: _verifiedPersonal);
        return;
      }
      _rejectAccess(
        'Your account or workplace access changed. Checking current authorization.',
      );
      _checkSetup();
    });
    _authSubscription = widget.client.auth.onAuthStateChange.listen(
      (state) {
        final token = state.session?.accessToken;
        final id = state.session?.user.id;
        if (token == _sessionToken && id == _sessionUserId) return;
        final changedUser = id != _sessionUserId;
        _sessionToken = token;
        _sessionUserId = id;
        ++_loadVersion;
        _watchSessionExpiry();
        if (state.session == null) {
          _refreshQueued = false;
          _rejectAccess('Your session has ended. Please sign in again.');
        } else {
          if (changedUser) _rejectAccess('Checking your new account access.');
          _checkSetup();
        }
      },
      onError: (Object error, StackTrace stack) {
        _refreshQueued = false;
        final session = widget.client.auth.currentSession;
        final personal =
            verificationUnavailable(error) &&
            _verifiedPersonal &&
            !_offlineRevoked &&
            session != null &&
            !_expired(session) &&
            session.user.id == _sessionUserId;
        if (verificationUnavailable(error) &&
            _access != null &&
            session != null &&
            !_expired(session)) {
          _degradeAccess(personalOffline: personal);
        } else {
          _rejectAccess(
            'Could not confirm your session. Please try again.',
            personalOffline: personal,
          );
        }
      },
    );
    _checkSetup();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    ++_loadVersion;
    _resumeTimer?.cancel();
    _expiryTimer?.cancel();
    _reconnectTimer?.cancel();
    _authSubscription?.cancel();
    _accessSubscription?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _resumeTimer?.cancel();
    if (state == AppLifecycleState.resumed) {
      final session = widget.client.auth.currentSession;
      if (session == null || _expired(session)) {
        _rejectAccess(
          'Your session has expired. Please reconnect and try again.',
        );
      }
      // Coalesce rapid app switches without postponing a check already in flight.
      _resumeTimer = Timer(const Duration(milliseconds: 300), _checkSetup);
    }
  }

  bool _expired(Session session) =>
      session.expiresAt != null &&
      session.expiresAt! * 1000 <= DateTime.now().millisecondsSinceEpoch;

  void _watchSessionExpiry() {
    _expiryTimer?.cancel();
    final session = widget.client.auth.currentSession;
    if (session?.expiresAt == null) return;
    final delay = DateTime.fromMillisecondsSinceEpoch(
      session!.expiresAt! * 1000,
    ).difference(DateTime.now());
    _expiryTimer = Timer(delay.isNegative ? Duration.zero : delay, () {
      if (mounted &&
          widget.client.auth.currentSession?.accessToken ==
              session.accessToken) {
        _refreshQueued = false;
        _rejectAccess(
          'Your session has expired. Please reconnect and try again.',
        );
      }
    });
  }

  void _rejectAccess(String message, {bool personalOffline = false}) {
    if (!mounted) return;
    ++_loadVersion;
    _reconnectTimer?.cancel();
    _policy.block();
    if (!personalOffline) {
      _offlineRevoked = true;
      _verifiedPersonal = false;
      unawaited(LocalWorkStore(_ownerId).seal().catchError((Object _) {}));
    }
    Navigator.of(context).popUntil(
      (route) =>
          route.isFirst ||
          (personalOffline && route.settings.name == 'offline-personal'),
    );
    setState(() {
      _access = null;
      _needsSetup = false;
      _needsPassword = false;
      _mfaFactors = [];
      _offlineAllowed = personalOffline;
      _checking = false;
      _error = message;
    });
  }

  void _degradeAccess({required bool personalOffline}) {
    if (!mounted) return;
    FocusManager.instance.primaryFocus?.unfocus();
    _policy.block(
      preserveContext: _access != null,
      personalCache: personalOffline,
    );
    setState(() {
      _checking = false;
      _offlineAllowed = personalOffline;
    });
    _reconnectTimer?.cancel();
    _scheduleReconnect();
  }

  void _scheduleReconnect() {
    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(const Duration(seconds: 30), () {
      if (mounted &&
          WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed) {
        _checkSetup();
      }
    });
  }

  String _scopeOf(WorkspaceAccess access) =>
      (access.roles
              .map(
                (role) =>
                    '${role['role']}/${role['agency_id']}/${role['site_id']}',
              )
              .toList()
            ..sort())
          .join('|');

  Future<void> _checkSetup() {
    _resumeTimer?.cancel();
    if (_validation != null) {
      if (_runningVersion != _loadVersion) _refreshQueued = true;
      return _validation!;
    }
    final version = ++_loadVersion;
    _runningVersion = version;
    final session = widget.client.auth.currentSession;
    setState(() {
      _checking = true;
      _error = null;
    });
    _validation = _validate(version, session).whenComplete(() {
      _validation = null;
      _runningVersion = null;
      if (mounted && _refreshQueued) {
        _refreshQueued = false;
        _checkSetup();
      }
    });
    return _validation!;
  }

  Future<void> _validate(int version, Session? session) async {
    try {
      if (session == null) throw const FormatException('Missing session');
      final result = await _readAuthorization(
        version,
        session,
      ).timeout(const Duration(seconds: 15));
      if (!mounted || version != _loadVersion) return;
      if (_expired(session)) throw const FormatException('Expired session');
      _reconnectTimer?.cancel();
      if (result.access != null) {
        _policy.accept(session);
      } else {
        _policy.block();
      }
      if (_access != null &&
          (result.access == null ||
              _scopeOf(_access!) != _scopeOf(result.access!))) {
        Navigator.of(context).popUntil((route) => route.isFirst);
      }
      setState(() {
        _needsSetup = result.needsSetup;
        _needsPassword = result.needsPassword;
        _mfaFactors = result.factors;
        _access = result.access;
        _offlineAllowed = false;
        _offlineRevoked = result.access == null;
        _verifiedPersonal =
            result.access?.roles.any((r) => r['role'] == 'personnel') ?? false;
      });
      final personal = _verifiedPersonal;
      final proofStore = LocalWorkStore(session.user.id);
      _proofWrites = _proofWrites
          .then((_) async {
            if (!personal) {
              await proofStore.remove('personal_access_proof');
            } else if (mounted && version == _loadVersion) {
              final scopes = result.access!.roles
                  .where((r) => r['role'] == 'personnel')
                  .map(scopeKey)
                  .toList();
              await saveOfflineAccess(
                session,
                store: proofStore,
                scopes: scopes,
              );
              if (mounted && version == _loadVersion) {
                unawaited(
                  PersonalSync.of(widget.client).synchronize(result.access!),
                );
              }
            }
          })
          .catchError((Object _) {});
      _watchSessionExpiry();
    } catch (error) {
      if (mounted && version == _loadVersion) {
        final disconnected = verificationUnavailable(error);
        final offline =
            disconnected &&
            !_offlineRevoked &&
            session != null &&
            !_expired(session) &&
            (_verifiedPersonal ||
                (_access == null && await mayReadOfflinePersonalWork(session)));
        if (!mounted || version != _loadVersion) return;
        if (disconnected &&
            _access != null &&
            session != null &&
            !_expired(session)) {
          _degradeAccess(personalOffline: offline);
          return;
        }
        _rejectAccess(
          disconnected
              ? 'Connection unavailable. Reconnect to verify workplace access.'
              : 'Could not load your workplace access. Please try again.',
          personalOffline: offline,
        );
        if (disconnected) _scheduleReconnect();
      }
    } finally {
      if (mounted && version == _loadVersion) setState(() => _checking = false);
    }
  }

  Future<
    ({
      bool needsSetup,
      bool needsPassword,
      WorkspaceAccess? access,
      List<Factor> factors,
    })
  >
  _readAuthorization(int version, Session session) async {
    void ensureCurrent() {
      if (!mounted ||
          version != _loadVersion ||
          widget.client.auth.currentSession?.accessToken !=
              session.accessToken ||
          widget.client.auth.currentUser?.id != session.user.id) {
        throw const FormatException('Stale authorization check');
      }
    }

    final user = (await widget.client.auth.getUser(session.accessToken)).user;
    ensureCurrent();
    if (user == null || user.id != session.user.id || user.isAnonymous) {
      throw const FormatException('Invalid authenticated user');
    }
    final factors = (user.factors ?? [])
        .where((factor) => factor.status == FactorStatus.verified)
        .toList();
    if (factors.isNotEmpty &&
        widget.client.auth.mfa.getAuthenticatorAssuranceLevel().currentLevel !=
            AuthenticatorAssuranceLevels.aal2) {
      return (
        needsSetup: false,
        needsPassword: false,
        access: null,
        factors: factors,
      );
    }
    if (widget.recovering) {
      return (
        needsSetup: false,
        needsPassword: true,
        access: null,
        factors: <Factor>[],
      );
    }
    final result = await widget.client.rpc('needs_company_setup');
    ensureCurrent();
    if (result is! bool) {
      throw const FormatException('Invalid setup response');
    }
    final needsPassword = await widget.client.rpc('needs_password_setup');
    ensureCurrent();
    if (needsPassword is! bool) {
      throw const FormatException('Invalid password setup response');
    }
    WorkspaceAccess? access;
    if (!result && !needsPassword) {
      final id = session.user.id;
      final profile = await widget.client
          .from('profiles')
          .select('id,full_name,is_active')
          .eq('id', id)
          .eq('is_active', true)
          .maybeSingle();
      ensureCurrent();
      if (profile == null ||
          profile['id'] != id ||
          profile['is_active'] != true) {
        return (
          needsSetup: false,
          needsPassword: false,
          access: null,
          factors: <Factor>[],
        );
      }
      final roles = await readWorkspaceRows(
        widget.client
            .from('role_assignments')
            .select('role,agency_id,site_id')
            .eq('user_id', id)
            .eq('is_active', true),
      );
      ensureCurrent();
      if (roles.any(
        (r) =>
            !['admin', 'supervisor', 'personnel'].contains(r['role']) ||
            (r['role'] == 'admin'
                ? r['agency_id'] != null || r['site_id'] != null
                : r['agency_id'] is! String) ||
            (r['site_id'] != null && r['site_id'] is! String) ||
            (r['role'] == 'personnel' && r['site_id'] == null),
      )) {
        throw const FormatException('Invalid workplace role');
      }
      if (roles.isNotEmpty) {
        access = WorkspaceAccess(
          fullName: profile['full_name'] as String,
          roles: roles,
        );
      }
    }
    return (
      needsSetup: result,
      needsPassword: needsPassword,
      access: access,
      factors: <Factor>[],
    );
  }

  Future<void> _signOut() async {
    setState(() {
      _busy = true;
      _error = null;
    });
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
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_error == null && _mfaFactors.isNotEmpty) {
      return MfaPage(
        client: widget.client,
        factors: _mfaFactors,
        onVerified: _checkSetup,
      );
    }
    if (_error == null && _access != null) {
      return WorkspacePage(
        key: ValueKey(_scopeOf(_access!)),
        client: widget.client,
        access: _access!,
        onRefreshAccess: _checkSetup,
      );
    }
    if (!_checking && _error == null && _needsPassword) {
      return ResetPasswordPage(
        client: widget.client,
        initialSetup: !widget.recovering,
        onSaved: widget.recovering ? null : _checkSetup,
      );
    }
    if (!_checking && _error == null && _needsSetup) {
      return CompanySetupPage(client: widget.client, onSaved: _checkSetup);
    }
    final statusIcon = _checking
        ? Icons.sync_outlined
        : _error != null
        ? Icons.wifi_off_outlined
        : Icons.person_search_outlined;
    final title = _checking
        ? 'Checking your access'
        : _error != null
        ? 'Unable to verify access'
        : 'Workspace access pending';
    final details = _checking
        ? 'Connecting to your workspace…'
        : _error != null
        ? _error!
        : 'Your account is connected. Ask your supervisor to assign your workplace.';
    return Scaffold(
      appBar: AppBar(
        title: const Row(
          children: [
            JanitraLogo(size: 32),
            SizedBox(width: 10),
            Text('JANITRA'),
          ],
        ),
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 460),
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            width: 52,
                            height: 52,
                            decoration: BoxDecoration(
                              color: Theme.of(context)
                                  .colorScheme
                                  .primaryContainer,
                              borderRadius: BorderRadius.circular(16),
                            ),
                            child: Icon(
                              statusIcon,
                              color: Theme.of(context)
                                  .colorScheme
                                  .onPrimaryContainer,
                              size: 27,
                            ),
                          ),
                          const SizedBox(height: 20),
                          Text(
                            title,
                            style: Theme.of(context).textTheme.headlineSmall,
                          ),
                          const SizedBox(height: 8),
                          Semantics(
                            liveRegion: true,
                            child: Text(
                              details,
                              style: TextStyle(
                                color: Theme.of(context)
                                    .colorScheme
                                    .onSurfaceVariant,
                                height: 1.5,
                              ),
                            ),
                          ),
                          if (_checking) ...[
                            const SizedBox(height: 20),
                            const LinearProgressIndicator(),
                          ],
                          if (widget.client.auth.currentUser?.email !=
                              null) ...[
                            const SizedBox(height: 18),
                            const Divider(height: 1),
                            const SizedBox(height: 12),
                            Text(
                              accountLabel(widget.client.auth.currentUser),
                              style: TextStyle(
                                fontSize: 13,
                                color: Theme.of(context)
                                    .colorScheme
                                    .onSurfaceVariant,
                              ),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  if (_offlineAllowed) ...[
                    OutlinedButton.icon(
                      onPressed: () => Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          settings: const RouteSettings(
                            name: 'offline-personal',
                          ),
                          builder: (_) => OfflineWorkPage(
                            owner: widget.client.auth.currentUser!.id,
                            client: widget.client,
                          ),
                        ),
                      ),
                      icon: const Icon(Icons.offline_pin_outlined),
                      label: const Text('View saved offline work'),
                    ),
                    const SizedBox(height: 10),
                  ],
                  FilledButton.icon(
                    onPressed: _checking ? null : _checkSetup,
                    icon: const Icon(Icons.refresh),
                    label: Text(
                      _error != null ? 'Try again' : 'Refresh access',
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextButton(
                    onPressed: _busy ? null : _signOut,
                    child: Text(_busy ? 'Signing out…' : 'Sign out'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
