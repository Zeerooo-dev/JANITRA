import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// A small, keyboard-aware editor shared by workplace and company management.
/// The caller owns authorization and persistence; this widget only collects a name.
class NameEditor extends StatefulWidget {
  const NameEditor({
    super.key,
    required this.title,
    required this.label,
    this.initialName = '',
    this.clients,
    this.contextLabel,
    required this.onSave,
  });

  final String title;
  final String label;
  final String initialName;
  final List<Map<String, dynamic>>? clients;
  final String? contextLabel;
  final Future<void> Function(String, String?) onSave;

  @override
  State<NameEditor> createState() => _NameEditorState();
}

class _NameEditorState extends State<NameEditor> {
  final _form = GlobalKey<FormState>();
  late final _name = TextEditingController(text: widget.initialName);
  late String? _clientId = widget.clients?.length == 1
      ? widget.clients!.single['id'] as String
      : null;
  bool _busy = false;
  String? _error;

  bool get _editing => widget.initialName.isNotEmpty;
  bool get _workplace => widget.label == 'Workplace name';

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_busy || !_form.currentState!.validate()) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.onSave(_name.text.trim(), _clientId);
      if (mounted) Navigator.pop(context, true);
    } catch (error) {
      if (mounted) {
        setState(
          () => _error = error is PostgrestException && error.code == '23505'
              ? 'This name already exists. Choose a different name.'
              : 'Could not save. Check your connection and workplace access, then try again.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bottomInset = MediaQuery.viewInsetsOf(context).bottom;
    return PopScope(
      canPop: !_busy,
      child: SafeArea(
        top: false,
        child: AnimatedPadding(
          duration: MediaQuery.disableAnimationsOf(context)
              ? Duration.zero
              : const Duration(milliseconds: 180),
          curve: Curves.easeOut,
          padding: EdgeInsets.only(bottom: bottomInset),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 18),
            child: SingleChildScrollView(
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
              child: Form(
                key: _form,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        Container(
                          width: 44,
                          height: 44,
                          decoration: BoxDecoration(
                            color: theme.colorScheme.primaryContainer,
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: Icon(
                            _workplace
                                ? Icons.location_on_outlined
                                : Icons.business_outlined,
                            color: theme.colorScheme.onPrimaryContainer,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            widget.title,
                            style: theme.textTheme.titleLarge,
                          ),
                        ),
                        IconButton(
                          tooltip: 'Close',
                          onPressed: _busy
                              ? null
                              : () => Navigator.pop(context, false),
                          icon: const Icon(Icons.close),
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),
                    if (widget.clients != null) ...[
                      Text('Client company', style: theme.textTheme.labelLarge),
                      const SizedBox(height: 8),
                      DropdownButtonFormField<String>(
                        initialValue: _clientId,
                        isExpanded: true,
                        itemHeight: null,
                        decoration: const InputDecoration(
                          hintText: 'Choose a company',
                          prefixIcon: Icon(Icons.apartment_outlined),
                        ),
                        items: widget.clients!
                            .map(
                              (c) => DropdownMenuItem(
                                value: c['id'] as String,
                                child: Text(
                                  c['name'] as String,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            )
                            .toList(),
                        onChanged: _busy
                            ? null
                            : (value) => setState(() => _clientId = value),
                        validator: (value) =>
                            value == null ? 'Choose a client company.' : null,
                      ),
                      const SizedBox(height: 16),
                    ],
                    if (widget.contextLabel != null) ...[
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 10,
                        ),
                        decoration: BoxDecoration(
                          color: theme.colorScheme.surfaceContainerLow,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.apartment_outlined, size: 19),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                widget.contextLabel!,
                                style: theme.textTheme.bodyMedium,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                    ],
                    Text(widget.label, style: theme.textTheme.labelLarge),
                    const SizedBox(height: 8),
                    TextFormField(
                      controller: _name,
                      enabled: !_busy,
                      autofocus: false,
                      maxLength: 200,
                      textCapitalization: TextCapitalization.words,
                      textInputAction: TextInputAction.done,
                      onFieldSubmitted: (_) => _save(),
                      decoration: InputDecoration(
                        hintText: _workplace
                            ? 'e.g. Main Office'
                            : 'Enter name',
                        prefixIcon: Icon(
                          _workplace
                              ? Icons.place_outlined
                              : Icons.edit_outlined,
                        ),
                        counterText: '',
                      ),
                      validator: (value) =>
                          value == null || value.trim().isEmpty
                          ? 'Enter a name.'
                          : null,
                    ),
                    if (_error != null) ...[
                      const SizedBox(height: 10),
                      Semantics(
                        liveRegion: true,
                        child: Text(
                          _error!,
                          style: TextStyle(color: theme.colorScheme.error),
                        ),
                      ),
                    ],
                    const SizedBox(height: 24),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: _busy
                                ? null
                                : () => Navigator.pop(context, false),
                            child: const Text('Cancel'),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: FilledButton(
                            onPressed: _busy ? null : _save,
                            child: _busy
                                ? const SizedBox(
                                    height: 20,
                                    width: 20,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  )
                                : Text(_editing ? 'Save changes' : 'Add'),
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
      ),
    );
  }
}
