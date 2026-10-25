import 'package:flutter/material.dart';

import 'dart:async';

import '../workspace/function_message.dart';
import '../../core/secret_text_form_field.dart';

class WorkField {
  const WorkField(
    this.keyName,
    this.label, {
    this.value = '',
    this.optional = false,
    this.secret = false,
    this.lines = 1,
    this.choices,
    this.choicesFor,
    this.validate,
    this.input = WorkFieldInput.text,
  });
  final String keyName, label, value;
  final bool optional, secret;
  final int lines;
  final Map<String, String>? choices;
  final Map<String, String> Function(Map<String, String?>)? choicesFor;
  final String? Function(String)? validate;
  final WorkFieldInput input;
}

enum WorkFieldInput { text, date, time, timeRanges }

class WorkForm extends StatefulWidget {
  const WorkForm({
    super.key,
    required this.title,
    required this.fields,
    required this.save,
    this.initialDays,
    this.button = 'Save',
    this.description,
    this.checklist = const [],
    this.initialChecks = const {},
    this.onDraftChanged,
    this.sheet = false,
  });
  final String title, button;
  final bool sheet;
  final String? description;
  final List<WorkField> fields;
  final List<int>? initialDays;
  final Future<void> Function(Map<String, dynamic>) save;
  final List<Map<String, dynamic>> checklist;
  final Map<String, bool> initialChecks;
  final Future<void> Function(Map<String, dynamic>)? onDraftChanged;
  @override
  State<WorkForm> createState() => _WorkFormState();
}

class _WorkFormState extends State<WorkForm> with WidgetsBindingObserver {
  final _form = GlobalKey<FormState>();
  final _values = <String, String?>{};
  final _controllers = <String, TextEditingController>{};
  late final Set<int> _days = {...?widget.initialDays};
  bool _busy = false;
  String? _error;
  late final Map<String, bool> _checks = Map.of(widget.initialChecks);
  Timer? _draftTimer;
  bool _dirty = false;
  Future<void> _draftWrites = Future.value();
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    for (final field in widget.fields) {
      _values[field.keyName] = field.value.isEmpty ? null : field.value;
      _controllers[field.keyName] = TextEditingController(text: field.value);
      if (!field.secret) {
        _controllers[field.keyName]!.addListener(_draftChanged);
      }
    }
  }

  @override
  void dispose() {
    _draftTimer?.cancel();
    _flushDraft();
    WidgetsBinding.instance.removeObserver(this);
    for (final c in _controllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) {
      _draftTimer?.cancel();
      _flushDraft();
      for (final f in widget.fields.where((f) => f.secret)) {
        _controllers[f.keyName]!.clear();
      }
    }
  }

  void _draftChanged() {
    if (widget.onDraftChanged == null) return;
    _dirty = true;
    _draftTimer?.cancel();
    _draftTimer = Timer(const Duration(milliseconds: 400), _flushDraft);
  }

  void _flushDraft() {
    if (!_dirty || widget.onDraftChanged == null) return;
    _dirty = false;
    final data = <String, dynamic>{
      for (final f in widget.fields.where((f) => !f.secret))
        f.keyName: _controllers[f.keyName]!.text,
      'checklist_results': Map.of(_checks),
    };
    _draftWrites = _draftWrites
        .then((_) => widget.onDraftChanged!(data))
        .catchError((Object _) {
          if (mounted) {
            setState(
              () => _error = 'Could not save this draft on the device. Keep this screen open and retry.',
            );
          }
        });
  }

  Future<void> _save() async {
    if (_busy || !_form.currentState!.validate()) return;
    if (widget.initialDays != null && _days.isEmpty) {
      setState(() => _error = 'Choose at least one working day.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final data = <String, dynamic>{};
      for (final f in widget.fields) {
        final value = f.choices != null || f.choicesFor != null
            ? _values[f.keyName]
            : f.secret
            ? _controllers[f.keyName]!.text
            : _controllers[f.keyName]!.text.trim();
        data[f.keyName] = value == null || value.isEmpty ? null : value;
      }
      if (widget.initialDays != null) data['weekdays'] = _days.toList()..sort();
      if (widget.checklist.isNotEmpty) {
        data['checklist_results'] = Map.of(_checks);
      }
      _draftTimer?.cancel();
      _flushDraft();
      await _draftWrites;
      await widget.save(data);
      if (mounted) Navigator.pop(context, true);
    } catch (error) {
      if (mounted) {
        setState(
          () => _error = error is FormatException
              ? error.message
              : functionMessage(error),
        );
      }
    } finally {
      if (mounted) {
        for (final f in widget.fields.where((f) => f.secret)) {
          _controllers[f.keyName]!.clear();
        }
        setState(() => _busy = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_busy,
    child: widget.sheet ? _sheet(context) : _dialog(context),
  );

  Widget _formContent() => Form(
    key: _form,
    child: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (widget.description != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: Text(widget.description!),
          ),
        for (final f in widget.fields)
          Padding(padding: const EdgeInsets.only(bottom: 14), child: _field(f)),
        if (widget.checklist.isNotEmpty) ...[
          Text(
            'Checklist: ${widget.checklist.where((item) => _checks[item['id']] == true).length} of ${widget.checklist.length} completed',
          ),
          for (final item in widget.checklist)
            CheckboxListTile(
              title: Text(item['label'] as String),
              value: _checks[item['id']] ?? false,
              controlAffinity: ListTileControlAffinity.leading,
              onChanged: _busy
                  ? null
                  : (value) {
                      setState(
                        () => _checks[item['id'] as String] = value ?? false,
                      );
                      _draftChanged();
                    },
            ),
        ],
        if (widget.initialDays != null) ...[
          const Text(
            'Working days',
            style: TextStyle(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 7,
            runSpacing: 3,
            children: List.generate(
              7,
              (i) => FilterChip(
                label: Text(
                  const ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'][i],
                ),
                selected: _days.contains(i + 1),
                onSelected: _busy
                    ? null
                    : (selected) => setState(
                        () => selected ? _days.add(i + 1) : _days.remove(i + 1),
                      ),
              ),
            ),
          ),
        ],
        if (_error != null)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Semantics(
              liveRegion: true,
              child: Text(
                _error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ),
          ),
      ],
    ),
  );

  List<Widget> _actions() => [
    OutlinedButton(
      onPressed: _busy ? null : () => Navigator.pop(context, false),
      child: const Text('Cancel'),
    ),
    FilledButton(
      style: widget.button.toLowerCase().startsWith('delete')
          ? FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
              foregroundColor: Theme.of(context).colorScheme.onError,
            )
          : null,
      onPressed: _busy ? null : _save,
      child: Text(_busy ? 'Saving…' : widget.button),
    ),
  ];

  Widget _dialog(BuildContext context) => AlertDialog(
    scrollable: true,
    title: Text(widget.title),
    titleTextStyle: Theme.of(context).textTheme.titleLarge,
    contentPadding: const EdgeInsets.fromLTRB(20, 14, 20, 8),
    actionsPadding: const EdgeInsets.fromLTRB(18, 4, 18, 14),
    content: SizedBox(width: 390, child: _formContent()),
    actions: _actions(),
  );

  Widget _sheet(BuildContext context) => SafeArea(
    top: false,
    child: Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.90,
          maxWidth: 620,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 10),
            Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.outlineVariant,
                borderRadius: BorderRadius.circular(4),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(22, 18, 12, 12),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      widget.title,
                      style: Theme.of(context).textTheme.titleLarge,
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
            ),
            Flexible(
              child: SingleChildScrollView(
                keyboardDismissBehavior:
                    ScrollViewKeyboardDismissBehavior.onDrag,
                padding: const EdgeInsets.fromLTRB(22, 0, 22, 14),
                child: _formContent(),
              ),
            ),
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 12, 18, 14),
              child: widget.button.length > 20
                  ? Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _actions()[1],
                        const SizedBox(height: 4),
                        _actions()[0],
                      ],
                    )
                  : Row(
                      children: [
                        Expanded(child: _actions()[0]),
                        const SizedBox(width: 12),
                        Expanded(child: _actions()[1]),
                      ],
                    ),
            ),
          ],
        ),
      ),
    ),
  );

  String _formatDate(DateTime date) =>
      '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
  String _formatTime(TimeOfDay time) =>
      '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';
  TimeOfDay _parseTime(String value) {
    try {
      final minutes = clockMinute(value);
      return TimeOfDay(hour: minutes ~/ 60, minute: minutes % 60);
    } catch (_) {
      return const TimeOfDay(hour: 8, minute: 0);
    }
  }

  Future<void> _pickDate(WorkField field) async {
    if (_busy) return;
    final controller = _controllers[field.keyName]!;
    final now = DateTime.now();
    final current = DateTime.tryParse(controller.text);
    final picked = await showDatePicker(
      context: context,
      initialDate: current ?? now,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
      helpText: field.label,
      initialEntryMode: DatePickerEntryMode.calendar,
    );
    if (picked != null && mounted) {
      setState(() => controller.text = _formatDate(picked));
    }
  }

  Future<void> _pickTime(WorkField field) async {
    if (_busy) return;
    final controller = _controllers[field.keyName]!;
    final picked = await showTimePicker(
      context: context,
      initialTime: _parseTime(controller.text),
      helpText: field.label,
      initialEntryMode: TimePickerEntryMode.dial,
    );
    if (picked != null && mounted) {
      setState(() => controller.text = _formatTime(picked));
    }
  }

  Future<void> _editTimeRange(WorkField field, int? index) async {
    if (_busy) return;
    final controller = _controllers[field.keyName]!;
    final ranges = controller.text
        .split('\n')
        .where((line) => line.trim().isNotEmpty)
        .toList();
    final old = index == null ? null : ranges[index].split('-');
    final start = await showTimePicker(
      context: context,
      initialTime: _parseTime(old?.first ?? '07:00'),
      helpText: 'Shift starts',
      initialEntryMode: TimePickerEntryMode.dial,
    );
    if (start == null || !mounted) return;
    final end = await showTimePicker(
      context: context,
      initialTime: _parseTime(old != null && old.length > 1 ? old[1] : '12:00'),
      helpText: 'Shift ends',
      initialEntryMode: TimePickerEntryMode.dial,
    );
    if (end == null || !mounted) return;
    final text = '${_formatTime(start)}-${_formatTime(end)}';
    if (index == null) {
      ranges.add(text);
    } else {
      ranges[index] = text;
    }
    setState(() => controller.text = ranges.join('\n'));
  }

  Widget _timeRangesField(WorkField f, String? Function(String?) validate) {
    final controller = _controllers[f.keyName]!;
    final rows = controller.text
        .split('\n')
        .where((line) => line.trim().isNotEmpty)
        .toList();
    return FormField<String>(
      key: ValueKey('ranges-${f.keyName}'),
      initialValue: controller.text,
      validator: (value) {
        final requiredError = validate(value);
        if (requiredError != null) return requiredError;
        for (final line
            in (value ?? '').split('\n').where((v) => v.trim().isNotEmpty)) {
          final parts = line.split('-');
          if (parts.length != 2 ||
              validTime(parts[0]) != null ||
              validTime(parts[1]) != null) {
            return 'Choose a valid start and end time.';
          }
        }
        return null;
      },
      builder: (state) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(f.label, style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 8),
          for (var i = 0; i < rows.length; i++)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _busy
                          ? null
                          : () async {
                              await _editTimeRange(f, i);
                              if (mounted && state.mounted) {
                                state.didChange(controller.text);
                              }
                            },
                      icon: const Icon(Icons.schedule, size: 18),
                      label: Text(rows[i].replaceFirst('-', '  –  ')),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Remove time range',
                    onPressed: _busy
                        ? null
                        : () {
                            final updated = [...rows]..removeAt(i);
                            setState(
                              () => controller.text = updated.join('\n'),
                            );
                            state.didChange(controller.text);
                          },
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
            ),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: _busy
                  ? null
                  : () async {
                      await _editTimeRange(f, null);
                      if (mounted && state.mounted) {
                        state.didChange(controller.text);
                      }
                    },
              icon: const Icon(Icons.add_alarm_outlined),
              label: Text(
                rows.isEmpty ? 'Add time range' : 'Add another time range',
              ),
            ),
          ),
          if (state.hasError)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                state.errorText!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ),
        ],
      ),
    );
  }

  Widget _field(WorkField f) {
    final options = f.choicesFor?.call(_values) ?? f.choices;
    String? validate(String? value) {
      if (!f.optional && (value == null || value.trim().isEmpty)) {
        return 'Enter ${f.label.toLowerCase()}.';
      }
      return value == null || value.isEmpty ? null : f.validate?.call(value);
    }

    if (f.input == WorkFieldInput.timeRanges) {
      return _timeRangesField(f, validate);
    }
    if (f.input == WorkFieldInput.date || f.input == WorkFieldInput.time) {
      return _labeledInput(
        f.label,
        TextFormField(
          controller: _controllers[f.keyName],
          readOnly: true,
          enabled: !_busy,
          decoration: InputDecoration(
            hintText: f.input == WorkFieldInput.date
                ? 'Choose date'
                : 'Choose time',
            prefixIcon: Icon(
              f.input == WorkFieldInput.date
                  ? Icons.calendar_month_outlined
                  : Icons.access_time_outlined,
            ),
            suffixIcon: f.optional && _controllers[f.keyName]!.text.isNotEmpty
                ? IconButton(
                    tooltip: 'Clear ${f.label}',
                    onPressed: _busy
                        ? null
                        : () =>
                              setState(() => _controllers[f.keyName]!.clear()),
                    icon: const Icon(Icons.close),
                  )
                : const Icon(Icons.arrow_drop_down),
          ),
          onTap: f.input == WorkFieldInput.date
              ? () => _pickDate(f)
              : () => _pickTime(f),
          validator: validate,
        ),
      );
    }
    if (options != null) {
      if (!options.containsKey(_values[f.keyName])) _values[f.keyName] = null;
      return _labeledInput(
        f.label,
        DropdownButtonFormField<String>(
          key: ValueKey('${f.keyName}/${options.keys.join()}'),
          initialValue: _values[f.keyName],
          isExpanded: true,
          decoration: const InputDecoration(),
          hint: const Text('Select an option'),
          items: options.entries
              .map(
                (e) => DropdownMenuItem(
                  value: e.key,
                  child: Text(e.value, overflow: TextOverflow.ellipsis),
                ),
              )
              .toList(),
          itemHeight: null,
          onChanged: _busy
              ? null
              : (value) => setState(() => _values[f.keyName] = value),
          validator: validate,
        ),
      );
    }
    if (f.secret) {
      return _labeledInput(
        f.label,
        SecretTextFormField(
          controller: _controllers[f.keyName]!,
          enabled: !_busy,
          visibilityLabel: f.keyName == 'pin' ? 'PIN' : 'password',
          keyboardType: f.keyName == 'pin' ? TextInputType.number : null,
          autofillHints: f.keyName == 'password'
              ? const [AutofillHints.password]
              : null,
          validator: validate,
        ),
      );
    }
    return _labeledInput(
      f.label,
      TextFormField(
        controller: _controllers[f.keyName],
        enabled: !_busy,
        maxLines: f.lines,
        validator: validate,
      ),
    );
  }

  // A fixed label cannot overlap a prefilled value or dropdown selection.
  // This also keeps the form legible at larger Android font sizes.
  Widget _labeledInput(String label, Widget input) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Text(
        label,
        style: Theme.of(context).textTheme.labelLarge
            ?.copyWith(fontWeight: FontWeight.w600),
      ),
      const SizedBox(height: 7),
      input,
    ],
  );
}

String? validDate(String value) {
  final d = DateTime.tryParse(value);
  return d == null ||
          '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}' !=
              value
      ? 'Use YYYY-MM-DD.'
      : null;
}

int clockMinute(String value) {
  final match = RegExp(r'^(\d{1,2}):(\d{2})$').firstMatch(value.trim());
  if (match == null) {
    throw const FormatException('Use times such as 07:00 or 16:00.');
  }
  final h = int.parse(match[1]!), m = int.parse(match[2]!);
  if (h > 23 || m > 59) throw const FormatException('Choose a valid time.');
  return h * 60 + m;
}

String? validTime(String value) {
  try {
    clockMinute(value);
    return null;
  } catch (_) {
    return 'Use HH:mm.';
  }
}
