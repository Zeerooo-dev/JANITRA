import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/auth_callback.dart';
import '../../core/app_theme.dart';
import 'account_setup_page.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({super.key, required this.client});
  final SupabaseClient client;

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _form = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _obscure = true;
  bool _busy = false;
  String? _message;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  String? _validateEmail(String? value) {
    final email = value?.trim() ?? '';
    return (RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(email) ||
            RegExp(r'^[a-zA-Z0-9][a-zA-Z0-9._-]{2,31}$').hasMatch(email))
        ? null
        : 'Enter your username or email address.';
  }

  Future<void> _signIn() async {
    if (_busy || !_form.currentState!.validate()) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      final identifier = _email.text.trim();
      if (identifier.contains('@')) {
        await widget.client.auth.signInWithPassword(
          email: identifier,
          password: _password.text,
        );
      } else {
        final response = await widget.client.functions.invoke(
          'personnel-auth',
          body: {
            'action': 'login',
            'identifier': identifier.toLowerCase(),
            'password': _password.text,
          },
        );
        final data = response.data;
        final session = data is Map ? data['session'] : null;
        final refresh = session is Map ? session['refresh_token'] : null;
        if (refresh is! String || refresh.isEmpty) {
          throw const FormatException('No authenticated session');
        }
        await widget.client.auth.setSession(refresh);
      }
    } on FunctionException {
      if (mounted) {
        setState(
          () => _message = 'Could not sign in. Check your username and password, or contact your Supervisor.',
        );
      }
    } on AuthException {
      if (mounted) {
        setState(
          () => _message = 'Could not sign in. Check your email and password, or contact your supervisor.',
        );
      }
    } catch (_) {
      if (mounted) {
        setState(
          () => _message = 'Could not connect. Check your internet connection and try again.',
        );
      }
    } finally {
      if (mounted) {
        _password.clear();
        setState(() => _busy = false);
      }
    }
  }

  Future<void> _recoverPassword() async {
    if (_busy) return;
    if (!RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(_email.text.trim())) {
      setState(
        () => _message = 'Enter an email address for email recovery. For username accounts, use Set up or recover Personnel account.',
      );
      return;
    }
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      await widget.client.auth.resetPasswordForEmail(
        _email.text.trim(),
        redirectTo: authRedirectUrl,
      );
      if (mounted) {
        setState(
          () => _message = 'If an account exists for this email, recovery instructions have been sent.',
        );
      }
    } catch (_) {
      if (mounted) {
        setState(
          () => _message = 'Could not request password recovery. Please try again or contact your supervisor.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            return SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  minHeight: (constraints.maxHeight - 48).clamp(
                    0,
                    double.infinity,
                  ),
                ),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 430),
                    child: AutofillGroup(
                      child: Form(
                        key: _form,
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            const Center(child: JanitraLogo()),
                            const SizedBox(height: 20),
                            const Text(
                              'Welcome to JANITRA',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontSize: 28,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(height: 8),
                            const Text(
                              'Sign in to continue',
                              textAlign: TextAlign.center,
                              style: TextStyle(fontSize: 16),
                            ),
                            const SizedBox(height: 32),
                            Card(
                              child: Padding(
                                padding: const EdgeInsets.all(24),
                                child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.stretch,
                                  children: [
                                    const Text(
                                      'Username or Email',
                                      style: TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                    const SizedBox(height: 8),
                                    Semantics(
                                      label: 'Username or Email',
                                      child: TextFormField(
                                        controller: _email,
                                        enabled: !_busy,
                                        keyboardType: TextInputType.text,
                                        textInputAction: TextInputAction.next,
                                        autofillHints: const [
                                          AutofillHints.username,
                                        ],
                                        autocorrect: false,
                                        decoration: const InputDecoration(
                                          hintText: 'you@company.com',
                                        ),
                                        validator: _validateEmail,
                                      ),
                                    ),
                                    const SizedBox(height: 24),
                                    const Text(
                                      'Password',
                                      style: TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                    const SizedBox(height: 8),
                                    Semantics(
                                      label: 'Password',
                                      child: TextFormField(
                                        controller: _password,
                                        enabled: !_busy,
                                        obscureText: _obscure,
                                        autocorrect: false,
                                        enableSuggestions: false,
                                        autofillHints: const [
                                          AutofillHints.password,
                                        ],
                                        textInputAction: TextInputAction.done,
                                        onFieldSubmitted: (_) => _signIn(),
                                        decoration: InputDecoration(
                                          hintText: 'Enter your password',
                                          suffixIcon: IconButton(
                                            tooltip: _obscure
                                                ? 'Show password'
                                                : 'Hide password',
                                            onPressed: _busy
                                                ? null
                                                : () => setState(
                                                    () => _obscure = !_obscure,
                                                  ),
                                            icon: Icon(
                                              _obscure
                                                  ? Icons.visibility_outlined
                                                  : Icons
                                                        .visibility_off_outlined,
                                            ),
                                          ),
                                        ),
                                        validator: (value) =>
                                            (value ?? '').isEmpty
                                            ? 'Enter your password.'
                                            : null,
                                      ),
                                    ),
                                    if (_message != null)
                                      Padding(
                                        padding: const EdgeInsets.only(top: 16),
                                        child: Semantics(
                                          liveRegion: true,
                                          child: Text(
                                            _message!,
                                            style: const TextStyle(
                                              fontSize: 16,
                                            ),
                                          ),
                                        ),
                                      ),
                                    const SizedBox(height: 24),
                                    FilledButton(
                                      onPressed: _busy ? null : _signIn,
                                      child: Text(
                                        _busy ? 'Please wait…' : 'Sign In',
                                      ),
                                    ),
                                    const SizedBox(height: 8),
                                    TextButton(
                                      onPressed: _busy
                                          ? null
                                          : _recoverPassword,
                                      child: const Text('Forgot Password?'),
                                    ),
                                    TextButton(
                                      onPressed: _busy
                                          ? null
                                          : () => Navigator.push(
                                              context,
                                              MaterialPageRoute<void>(
                                                builder: (_) =>
                                                    AccountSetupPage(
                                                      client: widget.client,
                                                    ),
                                              ),
                                            ),
                                      child: const Text(
                                        'Set up or recover Personnel account',
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}
