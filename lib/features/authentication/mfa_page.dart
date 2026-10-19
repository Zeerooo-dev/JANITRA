import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/account_label.dart';
import '../../core/secret_text_form_field.dart';

class MfaPage extends StatefulWidget {
  const MfaPage({
    super.key,
    required this.client,
    this.factors,
    this.onVerified,
  });
  final SupabaseClient client;
  final List<Factor>? factors;
  final Future<void> Function()? onVerified;

  @override
  State<MfaPage> createState() => _MfaPageState();
}

class _MfaPageState extends State<MfaPage> with WidgetsBindingObserver {
  final _form = GlobalKey<FormState>();
  final _code = TextEditingController();
  List<Factor> _factors = [];
  AuthMFAEnrollResponse? _enrollment;
  String? _factorId, _error;
  bool _loading = false, _busy = false, _verified = false, _showSecret = false;
  bool get _challenge => widget.factors != null;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    if (_challenge) {
      _selectFactors(widget.factors!);
    } else {
      _load();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) {
      _code.clear();
      if (_showSecret) setState(() => _showSecret = false);
    }
  }

  void _selectFactors(List<Factor> factors) {
    _factors = factors.where((f) => f.factorType == FactorType.totp).toList();
    if (!_factors.any((f) => f.id == _factorId)) {
      _factorId = _factors.isEmpty ? null : _factors.first.id;
    }
    _verified = factors.isNotEmpty;
  }

  @override
  void didUpdateWidget(covariant MfaPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_challenge) _selectFactors(widget.factors!);
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final user = (await widget.client.auth.getUser().timeout(
        const Duration(seconds: 15),
      )).user;
      if (user == null || user.id != widget.client.auth.currentUser?.id) {
        throw const FormatException('Invalid account');
      }
      if (mounted) {
        setState(
          () => _selectFactors(
            (user.factors ?? [])
                .where((f) => f.status == FactorStatus.verified)
                .toList(),
          ),
        );
      }
    } catch (_) {
      if (mounted) {
        setState(
          () => _error = 'Could not check two-step verification. Please retry.',
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _enroll() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final userId = widget.client.auth.currentUser?.id;
      final user = (await widget.client.auth.getUser()).user;
      if (user == null || user.id != userId || !mounted) return;
      // Remove only abandoned JANITRA setups; never remove a verified factor.
      for (final factor in user.factors ?? <Factor>[]) {
        if (factor.status == FactorStatus.unverified &&
            factor.factorType == FactorType.totp &&
            (factor.friendlyName?.startsWith('JANITRA ') ?? false)) {
          await widget.client.auth.mfa.unenroll(factor.id);
        }
      }
      if (!mounted || widget.client.auth.currentUser?.id != userId) return;
      final enrollment = await widget.client.auth.mfa.enroll(
        issuer: 'JANITRA',
        friendlyName: 'JANITRA ${DateTime.now().millisecondsSinceEpoch}',
      );
      if (enrollment.totp == null) {
        throw const FormatException('Missing setup key');
      }
      if (mounted) {
        setState(() {
          _enrollment = enrollment;
          _factorId = enrollment.id;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(
          () => _error =
              'Could not start setup. Check your connection and retry.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _verify() async {
    if (_busy || _factorId == null || !_form.currentState!.validate()) return;
    FocusScope.of(context).unfocus();
    final code = _code.text;
    _code.clear();
    final userId = widget.client.auth.currentUser?.id;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final challenge = await widget.client.auth.mfa.challenge(
        factorId: _factorId!,
      );
      if (!mounted || widget.client.auth.currentUser?.id != userId) return;
      await widget.client.auth.mfa.verify(
        factorId: _factorId!,
        challengeId: challenge.id,
        code: code,
      );
      if (!mounted) return;
      setState(() {
        _verified = true;
        _enrollment = null;
        _showSecret = false;
      });
      await widget.onVerified?.call();
    } on AuthRetryableFetchException {
      if (mounted) {
        setState(
          () => _error = 'Could not connect. Check your connection and retry.',
        );
      }
    } on AuthException {
      if (mounted) {
        setState(
          () => _error = 'Code could not be verified. Use the current code from your authenticator and retry.',
        );
      }
    } catch (_) {
      if (mounted) {
        setState(
          () => _error = 'Could not connect. Check your connection and retry.',
        );
      }
    } finally {
      if (mounted) {
        _code.clear();
        setState(() => _busy = false);
      }
    }
  }

  Future<void> _cancelSetup() async {
    if (_busy) return;
    final enrollment = _enrollment;
    if (enrollment == null) {
      Navigator.pop(context);
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.client.auth.mfa.unenroll(enrollment.id);
      if (mounted) Navigator.pop(context);
    } catch (_) {
      if (mounted) {
        setState(
          () => _error =
              'Could not cancel setup. Check your connection and retry.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _signOut() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.client.auth.signOut();
    } catch (_) {
      if (mounted) setState(() => _error = 'Could not sign out. Please retry.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _code.dispose();
    _enrollment = null;
    super.dispose();
  }

  Widget _step(BuildContext context, int number, String title, String details) {
    final scheme = Theme.of(context).colorScheme;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        CircleAvatar(
          radius: 17,
          backgroundColor: scheme.primaryContainer,
          foregroundColor: scheme.onPrimaryContainer,
          child: Text('$number', style: const TextStyle(fontWeight: FontWeight.w700)),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
              )),
              const SizedBox(height: 5),
              Text(details),
            ],
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return PopScope(
      canPop: !_busy && (_challenge || _enrollment == null),
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Two-Step Verification'),
          automaticallyImplyLeading: !_busy && _enrollment == null,
        ),
        body: SafeArea(
          child: _loading
              ? const Center(
                  child: CircularProgressIndicator(
                    semanticsLabel: 'Checking two-step verification',
                  ),
                )
              : Align(
                  alignment: Alignment.topCenter,
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 560),
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.all(20),
                      child: Form(
                        key: _form,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Container(
                              padding: const EdgeInsets.all(16),
                              decoration: BoxDecoration(
                                color: scheme.surfaceContainerLow,
                                borderRadius: BorderRadius.circular(16),
                              ),
                              child: Row(
                                children: [
                                  Icon(Icons.shield_outlined,
                                    size: 30, color: scheme.primary),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text('Protect your account',
                                          style: theme.textTheme.titleMedium?.copyWith(
                                            fontWeight: FontWeight.w700,
                                          )),
                                        const SizedBox(height: 4),
                                        Text(accountLabel(widget.client.auth.currentUser),
                                          style: theme.textTheme.bodyMedium),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 24),
                            if (_challenge) ...[
                              Text('Confirm it is you',
                                style: theme.textTheme.headlineSmall?.copyWith(
                                  fontWeight: FontWeight.w700,
                                )),
                              const SizedBox(height: 8),
                              const Text('Enter the current six-digit code from your authenticator app to continue.'),
                              if (_factors.isEmpty) ...[
                                const SizedBox(height: 16),
                                const Text('This account uses a verification method unavailable in JANITRA. Contact your supervisor for help.'),
                              ],
                              if (_factors.length > 1) ...[
                                const SizedBox(height: 16),
                                DropdownButtonFormField<String>(
                                  initialValue: _factorId,
                                  isExpanded: true,
                                  decoration: const InputDecoration(labelText: 'Authenticator'),
                                  items: _factors.map((f) => DropdownMenuItem(
                                    value: f.id,
                                    child: Text(f.friendlyName ?? 'Authenticator',
                                      overflow: TextOverflow.ellipsis),
                                  )).toList(),
                                  onChanged: _busy ? null : (value) => setState(() {
                                    _factorId = value;
                                    _code.clear();
                                  }),
                                ),
                              ],
                            ] else if (_verified) ...[
                              Row(
                                children: [
                                  Icon(Icons.check_circle_outline, color: scheme.primary, size: 28),
                                  const SizedBox(width: 10),
                                  Expanded(child: Text('Two-step verification is enabled.',
                                    style: theme.textTheme.titleLarge?.copyWith(
                                      fontWeight: FontWeight.w700,
                                    ))),
                                ],
                              ),
                              const SizedBox(height: 12),
                              const Text('Keep your authenticator app available. You will need its code when you sign in.'),
                            ] else if (_enrollment == null) ...[
                              Text('Add an authenticator',
                                style: theme.textTheme.headlineSmall?.copyWith(
                                  fontWeight: FontWeight.w700,
                                )),
                              const SizedBox(height: 10),
                              const Text('Use an authenticator app, such as Google Authenticator or Microsoft Authenticator, to protect your JANITRA account.'),
                              const SizedBox(height: 18),
                              _step(context, 1, 'Connect your app',
                                'Set up JANITRA in your authenticator app using a private setup key.'),
                              const SizedBox(height: 18),
                              _step(context, 2, 'Confirm the code',
                                'Enter the six-digit code shown in your app to finish.'),
                              const SizedBox(height: 16),
                              Text('Finishing setup signs out other sessions.',
                                style: theme.textTheme.bodySmall),
                              const SizedBox(height: 24),
                              FilledButton.icon(
                                onPressed: _busy ? null : _enroll,
                                icon: const Icon(Icons.lock_outline),
                                label: Text(_busy ? 'Starting setup…' : 'Set Up Authenticator'),
                              ),
                            ] else ...[
                              Text('Connect your authenticator',
                                style: theme.textTheme.headlineSmall?.copyWith(
                                  fontWeight: FontWeight.w700,
                                )),
                              const SizedBox(height: 18),
                              _step(context, 1, 'Add JANITRA to your app',
                                'Choose to enter a setup key manually. Use the key below, then return to JANITRA.'),
                              const SizedBox(height: 12),
                              Container(
                                padding: const EdgeInsets.all(14),
                                decoration: BoxDecoration(
                                  color: scheme.surfaceContainerLow,
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(color: scheme.outlineVariant),
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Text('Private setup key',
                                      style: TextStyle(fontWeight: FontWeight.w700)),
                                    const SizedBox(height: 10),
                                    if (_showSecret)
                                      SelectableText(_enrollment!.totp!.secret)
                                    else
                                      const Text('Hidden for your security'),
                                    const SizedBox(height: 6),
                                    Wrap(
                                      spacing: 8,
                                      children: [
                                        TextButton.icon(
                                          onPressed: _busy ? null : () => setState(
                                            () => _showSecret = !_showSecret),
                                          icon: Icon(_showSecret
                                            ? Icons.visibility_off_outlined
                                            : Icons.visibility_outlined),
                                          label: Text(_showSecret
                                            ? 'Hide Setup Key' : 'Show Setup Key'),
                                        ),
                                        if (_showSecret)
                                          TextButton.icon(
                                            onPressed: _busy ? null : () async {
                                              await Clipboard.setData(ClipboardData(
                                                text: _enrollment!.totp!.secret,
                                              ));
                                              if (context.mounted) {
                                                ScaffoldMessenger.of(context).showSnackBar(
                                                  const SnackBar(content: Text('Setup key copied. Keep it private.')),
                                                );
                                              }
                                            },
                                            icon: const Icon(Icons.copy_outlined),
                                            label: const Text('Copy Key'),
                                          ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 22),
                              _step(context, 2, 'Verify your code',
                                'Enter the six-digit code shown for JANITRA in your authenticator app.'),
                            ],
                            if ((_challenge && _factors.isNotEmpty) ||
                                _enrollment != null) ...[
                              const SizedBox(height: 16),
                              SecretTextFormField(
                                controller: _code,
                                enabled: !_busy,
                                visibilityLabel: 'code',
                                keyboardType: TextInputType.number,
                                autofillHints: const [AutofillHints.oneTimeCode],
                                inputFormatters: [
                                  FilteringTextInputFormatter.digitsOnly,
                                  LengthLimitingTextInputFormatter(6),
                                ],
                                decoration: const InputDecoration(
                                  labelText: 'Authenticator code',
                                  hintText: '6-digit code',
                                  prefixIcon: Icon(Icons.pin_outlined),
                                ),
                                validator: (value) => RegExp(r'^[0-9]{6}$')
                                    .hasMatch(value ?? '')
                                    ? null
                                    : 'Enter all six digits.',
                                onFieldSubmitted: (_) => _verify(),
                              ),
                              const SizedBox(height: 20),
                              FilledButton(
                                onPressed: _busy ? null : _verify,
                                child: Text(_busy ? 'Verifying…' : 'Verify Code'),
                              ),
                            ],
                            if (_error != null) ...[
                              const SizedBox(height: 16),
                              Semantics(
                                liveRegion: true,
                                child: Text(_error!, style: TextStyle(color: scheme.error)),
                              ),
                              if (!_challenge && _enrollment == null && !_verified)
                                TextButton(
                                  onPressed: _busy ? null : _load,
                                  child: const Text('Retry'),
                                ),
                            ],
                            const SizedBox(height: 12),
                            if (_challenge)
                              TextButton(
                                onPressed: _busy ? null : _signOut,
                                child: const Text('Sign Out'),
                              )
                            else if (_enrollment != null)
                              TextButton(
                                onPressed: _busy ? null : _cancelSetup,
                                child: const Text('Cancel Setup'),
                              ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
        ),
      ),
    );
  }
}
