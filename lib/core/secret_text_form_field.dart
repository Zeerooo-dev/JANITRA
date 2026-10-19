import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// A password, PIN, or recovery-code field with an accessible visibility toggle.
/// The toggle changes display only; it never changes the controller's value.
class SecretTextFormField extends StatefulWidget {
  const SecretTextFormField({
    super.key,
    required this.controller,
    this.enabled = true,
    this.decoration = const InputDecoration(),
    this.visibilityLabel = 'password',
    this.validator,
    this.autofillHints,
    this.keyboardType,
    this.inputFormatters,
    this.onFieldSubmitted,
  });

  final TextEditingController controller;
  final bool enabled;
  final InputDecoration decoration;
  final String visibilityLabel;
  final FormFieldValidator<String>? validator;
  final Iterable<String>? autofillHints;
  final TextInputType? keyboardType;
  final List<TextInputFormatter>? inputFormatters;
  final ValueChanged<String>? onFieldSubmitted;

  @override
  State<SecretTextFormField> createState() => _SecretTextFormFieldState();
}

class _SecretTextFormFieldState extends State<SecretTextFormField>
    with WidgetsBindingObserver {
  bool _visible = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didUpdateWidget(covariant SecretTextFormField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!widget.enabled || oldWidget.controller != widget.controller) {
      _visible = false;
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed && _visible && mounted) {
      setState(() => _visible = false);
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => TextFormField(
    controller: widget.controller,
    enabled: widget.enabled,
    obscureText: !_visible,
    autocorrect: false,
    enableSuggestions: false,
    keyboardType: widget.keyboardType,
    autofillHints: widget.autofillHints,
    inputFormatters: widget.inputFormatters,
    validator: widget.validator,
    onFieldSubmitted: widget.onFieldSubmitted,
    decoration: widget.decoration.copyWith(
      suffixIcon: IconButton(
        tooltip: _visible
            ? 'Hide ${widget.visibilityLabel}'
            : 'Show ${widget.visibilityLabel}',
        onPressed: widget.enabled
            ? () => setState(() => _visible = !_visible)
            : null,
        icon: Icon(
          _visible ? Icons.visibility_off_outlined : Icons.visibility_outlined,
        ),
      ),
    ),
  );
}
