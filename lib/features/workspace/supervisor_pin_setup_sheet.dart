import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/access_notice.dart';
import '../../core/access_policy.dart';
import 'function_message.dart';

/// Supervisor-owned or employee-scoped PIN setup/reset. Never exposes the PIN
/// through a text field; only the protected manage-pins endpoint can persist it.
class PinSetupSheet extends StatefulWidget {
  const PinSetupSheet({
    super.key,
    required this.client,
    required this.scope,
    required this.resetting,
    this.isEmployee = false,
    this.employeeName,
  });

  final SupabaseClient client;
  final Map<String, dynamic> scope;
  final bool resetting;
  final bool isEmployee;
  final String? employeeName;

  @override
  State<PinSetupSheet> createState() => _PinSetupSheetState();
}

class _PinSetupSheetState extends State<PinSetupSheet>
    with WidgetsBindingObserver {
  final _password = TextEditingController();
  int _step = 0;
  String _pin = '';
  String _entry = '';
  String? _error;
  bool _saving = false;
  bool _showPassword = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    AccessPolicy.of(widget.client).addListener(_accessChanged);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    AccessPolicy.of(widget.client).removeListener(_accessChanged);
    _clearSecrets();
    _password.dispose();
    super.dispose();
  }

  void _clearSecrets() {
    _pin = '';
    _entry = '';
    _password.clear();
  }

  void _accessChanged() {
    final policy = AccessPolicy.of(widget.client);
    if (policy.enforced && !policy.verified) _resetForSecurity();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) _resetForSecurity();
  }

  void _resetForSecurity() {
    _clearSecrets();
    if (mounted && !_saving) {
      setState(() {
        _step = 0;
        _error = null;
        _showPassword = false;
      });
    }
  }

  void _press(String value) {
    if (_saving || _step == 2) return;
    setState(() {
      _error = null;
      switch (value) {
        case 'Clear':
          _entry = '';
          break;
        case 'Backspace':
          if (_entry.isNotEmpty) {
            _entry = _entry.substring(0, _entry.length - 1);
          }
          break;
        default:
          if (_entry.length < 4) _entry += value;
          break;
      }
    });
  }

  void _continue() {
    if (_saving || _entry.length != 4) return;
    if (_step == 0) {
      setState(() {
        _pin = _entry;
        _entry = '';
        _step = 1;
        _error = null;
      });
    } else if (_step == 1) {
      if (_entry != _pin) {
        setState(() {
          _entry = '';
          _error = 'PINs do not match. Try again.';
        });
      } else {
        setState(() {
          _entry = '';
          _step = 2;
          _error = null;
        });
      }
    }
  }

  void _back() {
    if (_saving) return;
    setState(() {
      _error = null;
      _entry = '';
      if (_step == 2) {
        _password.clear();
        _step = 1;
      } else if (_step == 1) {
        _pin = '';
        _step = 0;
      }
    });
  }

  Future<void> _save() async {
    if (_saving || _step != 2 || _pin.length != 4) return;
    if (_password.text.isEmpty) {
      setState(() => _error = 'Enter your account password.');
      return;
    }
    final pin = _pin;
    final password = _password.text;
    setState(() {
      _saving = true;
      _error = null;
    });
    // The values are used for this one protected request only; clear UI state
    // immediately, and scrub the retained controller on every outcome.
    _clearSecrets();
    try {
      final response = await invokeProtected(
        widget.client,
        'manage-pins',
        body: {
          'action': 'set',
          ...widget.scope,
          'pin': pin,
          'password': password,
        },
      );
      if (response.data is! Map || response.data['configured'] != true) {
        throw const FormatException('PIN update not confirmed');
      }
      if (mounted) Navigator.of(context).pop(true);
    } catch (error) {
      if (mounted) setState(() => _error = functionMessage(error));
    } finally {
      if (mounted) {
        _clearSecrets();
        setState(() {
          _saving = false;
          _step = 0;
          _showPassword = false;
        });
      }
    }
  }

  Widget _indicators(ColorScheme colors) => Semantics(
    label: '${_entry.length} of 4 PIN digits entered',
    child: ExcludeSemantics(
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: List.generate(
          4,
          (index) => AnimatedContainer(
            duration: MediaQuery.disableAnimationsOf(context)
                ? Duration.zero
                : const Duration(milliseconds: 120),
            width: 19,
            height: 19,
            margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: index < _entry.length
                  ? colors.primary
                  : Colors.transparent,
              border: Border.all(color: colors.primary, width: 1.7),
            ),
          ),
        ),
      ),
    ),
  );

  Widget _keypad() => GridView.count(
    key: ValueKey(
      widget.isEmployee ? 'employee-pin-keypad' : 'supervisor-pin-keypad',
    ),
    shrinkWrap: true,
    physics: const NeverScrollableScrollPhysics(),
    crossAxisCount: 3,
    mainAxisExtent: 52,
    mainAxisSpacing: 8,
    crossAxisSpacing: 8,
    children: [
      for (final digit in [
        '1',
        '2',
        '3',
        '4',
        '5',
        '6',
        '7',
        '8',
        '9',
        'Clear',
        '0',
        'Backspace',
      ])
        OutlinedButton(
          style: OutlinedButton.styleFrom(padding: EdgeInsets.zero),
          onPressed: _saving ? null : () => _press(digit),
          child: digit == 'Backspace'
              ? const Icon(Icons.backspace_outlined, semanticLabel: 'Backspace')
              : Text(
                  digit,
                  style: TextStyle(fontSize: digit.length == 1 ? 21 : 12),
                ),
        ),
    ],
  );

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final view = MediaQuery.of(context);
    final availableHeight =
        (view.size.height -
                view.viewInsets.bottom -
                view.padding.top -
                view.padding.bottom)
            .clamp(200.0, double.infinity)
            .toDouble();
    final headings = [
      'Choose a new PIN',
      'Repeat your PIN',
      'Confirm your identity',
    ];
    final captions = [
      'Enter four digits.',
      'Enter the same four digits again.',
      widget.isEmployee
          ? 'Enter your Supervisor account password to save.'
          : 'Enter your account password to save the new PIN.',
    ];

    return PopScope(
      canPop: !_saving,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: EdgeInsets.only(bottom: view.viewInsets.bottom),
          child: Center(
            heightFactor: 1,
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxWidth: 440,
                maxHeight: availableHeight * 0.94,
              ),
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Center(
                      child: Container(
                        width: 36,
                        height: 4,
                        decoration: BoxDecoration(
                          color: colors.outlineVariant,
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            widget.isEmployee
                                ? (widget.resetting
                                      ? 'Reset Employee PIN'
                                      : 'Set Employee PIN')
                                : (widget.resetting
                                      ? 'Update Supervisor PIN'
                                      : 'Set Supervisor PIN'),
                            style: theme.textTheme.titleLarge,
                          ),
                        ),
                        IconButton(
                          tooltip: 'Close PIN setup',
                          icon: const Icon(Icons.close),
                          onPressed: _saving
                              ? null
                              : () => Navigator.pop(context),
                        ),
                      ],
                    ),
                    if (widget.isEmployee && widget.employeeName != null) ...[
                      Text(
                        'For ${widget.employeeName}',
                        style: theme.textTheme.bodyMedium,
                      ),
                      const SizedBox(height: 12),
                    ],
                    const SizedBox(height: 10),
                    LinearProgressIndicator(
                      value: (_step + 1) / 3,
                      minHeight: 4,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'Step ${_step + 1} of 3',
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: colors.primary,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Text(headings[_step], style: theme.textTheme.titleMedium),
                    const SizedBox(height: 5),
                    Text(captions[_step], style: theme.textTheme.bodySmall),
                    if (_step < 2) ...[
                      const SizedBox(height: 18),
                      _indicators(colors),
                      const SizedBox(height: 12),
                      _keypad(),
                    ] else ...[
                      const SizedBox(height: 22),
                      TextField(
                        key: ValueKey(
                          widget.isEmployee
                              ? 'employee-pin-password'
                              : 'supervisor-pin-password',
                        ),
                        controller: _password,
                        enabled: !_saving,
                        obscureText: !_showPassword,
                        autocorrect: false,
                        enableSuggestions: false,
                        keyboardType: TextInputType.visiblePassword,
                        textInputAction: TextInputAction.done,
                        autofillHints: const [AutofillHints.password],
                        decoration: InputDecoration(
                          labelText: 'Account password',
                          prefixIcon: const Icon(Icons.lock_outline),
                          suffixIcon: IconButton(
                            tooltip: _showPassword
                                ? 'Hide password'
                                : 'Show password',
                            icon: Icon(
                              _showPassword
                                  ? Icons.visibility_off_outlined
                                  : Icons.visibility_outlined,
                            ),
                            onPressed: _saving
                                ? null
                                : () => setState(
                                    () => _showPassword = !_showPassword,
                                  ),
                          ),
                        ),
                        onChanged: (_) => setState(() => _error = null),
                        onSubmitted: (_) => _save(),
                      ),
                    ],
                    if (_error != null) ...[
                      const SizedBox(height: 12),
                      Semantics(
                        liveRegion: true,
                        child: Text(
                          _error!,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: colors.error,
                          ),
                        ),
                      ),
                    ],
                    const SizedBox(height: 20),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: _saving
                                ? null
                                : _step == 0
                                ? () => Navigator.pop(context)
                                : _back,
                            child: Text(_step == 0 ? 'Cancel' : 'Back'),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: FilledButton(
                            onPressed: _saving
                                ? null
                                : _step == 2
                                ? _save
                                : _entry.length == 4
                                ? _continue
                                : null,
                            child: _saving
                                ? const SizedBox(
                                    height: 18,
                                    width: 18,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  )
                                : Text(_step == 2 ? 'Save PIN' : 'Continue'),
                          ),
                        ),
                      ],
                    ),
                    if (widget.resetting) ...[
                      const SizedBox(height: 12),
                      Text(
                        widget.isEmployee
                            ? 'The employee’s previous PIN stops working after saving.'
                            : 'Your previous PIN stops working after saving.',
                        textAlign: TextAlign.center,
                        style: theme.textTheme.bodySmall,
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
