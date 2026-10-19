import 'package:flutter/material.dart';

import '../../core/appearance_settings.dart';

class ColorPickerDialog extends StatefulWidget {
  const ColorPickerDialog({
    super.key,
    required this.first,
    required this.second,
    required this.accentOnly,
    required this.brightness,
  });
  final Color first, second;
  final bool accentOnly;
  final Brightness brightness;

  @override
  State<ColorPickerDialog> createState() => _ColorPickerDialogState();
}

class _ColorPickerDialogState extends State<ColorPickerDialog> {
  final _form = GlobalKey<FormState>();
  late Color _first = widget.first, _second = widget.second;
  late HSVColor _hsv = HSVColor.fromColor(_first);
  late final _hex = TextEditingController(text: hex(_first));
  bool _editingText = false;
  String? _message;

  static String hex(Color color) =>
      '#${color.toARGB32().toRadixString(16).substring(2).toUpperCase()}';

  @override
  void dispose() {
    _hex.dispose();
    super.dispose();
  }

  void _choose(HSVColor color, {bool updateHex = true}) {
    setState(() {
      _hsv = color;
      if (_editingText) {
        _second = color.toColor();
      } else {
        _first = color.toColor();
      }
      if (updateHex) _hex.text = hex(color.toColor());
      _message = null;
    });
    _form.currentState?.validate();
  }

  void _target(bool text) {
    setState(() {
      _editingText = text;
      _hsv = HSVColor.fromColor(text ? _second : _first);
      _hex.text = hex(_hsv.toColor());
      _message = null;
    });
    _form.currentState?.validate();
  }

  Widget _targetButton(
    String label,
    Color color,
    bool selected,
    VoidCallback onTap,
  ) => OutlinedButton.icon(
    style: selected
        ? OutlinedButton.styleFrom(
            side: BorderSide(
              color: Theme.of(context).colorScheme.primary,
              width: 2,
            ),
          )
        : null,
    onPressed: onTap,
    icon: Container(
      width: 24,
      height: 24,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(5),
        border: Border.all(color: Theme.of(context).colorScheme.outline),
      ),
      child: selected
          ? Icon(
              Icons.check,
              size: 18,
              color: colorContrast(color, Colors.white) >= 4.5
                  ? Colors.white
                  : Colors.black,
            )
          : null,
    ),
    label: Text('$label ${hex(color)}'),
  );

  Widget _slider(
    String label,
    double value,
    double max,
    ValueChanged<double> onChanged, {
    bool hue = false,
  }) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Text('$label: ${value.round()}${hue ? '°' : '%'}'),
      Stack(
        alignment: Alignment.center,
        children: [
          if (hue)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Container(
                height: 8,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(4),
                  gradient: const LinearGradient(
                    colors: [
                      Color(0xFFFF0000),
                      Color(0xFFFFFF00),
                      Color(0xFF00FF00),
                      Color(0xFF00FFFF),
                      Color(0xFF0000FF),
                      Color(0xFFFF00FF),
                      Color(0xFFFF0000),
                    ],
                  ),
                ),
              ),
            ),
          Semantics(
            label: label,
            child: Slider(
              key: ValueKey(label),
              value: value,
              min: 0,
              max: max,
              divisions: max.round(),
              activeColor: hue ? Colors.transparent : null,
              inactiveColor: hue ? Colors.transparent : null,
              semanticFormatterCallback: (v) =>
                  '${v.round()} ${hue ? 'degrees' : 'percent'}',
              onChanged: onChanged,
            ),
          ),
        ],
      ),
    ],
  );

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final contrast = colorContrast(_first, _second);
    return AlertDialog(
      title: Text(
        widget.accentOnly
            ? 'Custom accent'
            : '${widget.brightness == Brightness.dark ? 'Dark' : 'Light'} colors',
      ),
      content: SizedBox(
        width: 360,
        child: SingleChildScrollView(
          child: Form(
            key: _form,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (!widget.accentOnly) ...[
                  _targetButton(
                    'Background',
                    _first,
                    !_editingText,
                    () => _target(false),
                  ),
                  const SizedBox(height: 8),
                  _targetButton(
                    'Text',
                    _second,
                    _editingText,
                    () => _target(true),
                  ),
                  const SizedBox(height: 14),
                ],
                const Text(
                  'Drag to choose a color, or use the sliders and hex value.',
                ),
                const SizedBox(height: 12),
                Semantics(
                  label: 'Color area',
                  hint: 'Drag to adjust saturation and brightness. The sliders offer the same controls.',
                  child: AspectRatio(
                    aspectRatio: 1.7,
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        void pick(Offset position) => _choose(
                          _hsv
                              .withSaturation(
                                (position.dx / constraints.maxWidth).clamp(
                                  0,
                                  1,
                                ),
                              )
                              .withValue(
                                (1 - position.dy / constraints.maxHeight).clamp(
                                  0,
                                  1,
                                ),
                              ),
                        );
                        return GestureDetector(
                          key: const ValueKey('color-area'),
                          onPanDown: (event) => pick(event.localPosition),
                          onPanUpdate: (event) => pick(event.localPosition),
                          child: Stack(
                            children: [
                              Positioned.fill(
                                child: DecoratedBox(
                                  decoration: BoxDecoration(
                                    color: HSVColor.fromAHSV(
                                      1,
                                      _hsv.hue,
                                      1,
                                      1,
                                    ).toColor(),
                                  ),
                                ),
                              ),
                              const Positioned.fill(
                                child: DecoratedBox(
                                  decoration: BoxDecoration(
                                    gradient: LinearGradient(
                                      colors: [
                                        Colors.white,
                                        Colors.transparent,
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                              const Positioned.fill(
                                child: DecoratedBox(
                                  decoration: BoxDecoration(
                                    gradient: LinearGradient(
                                      begin: Alignment.topCenter,
                                      end: Alignment.bottomCenter,
                                      colors: [
                                        Colors.transparent,
                                        Colors.black,
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                              Positioned(
                                left:
                                    (_hsv.saturation * constraints.maxWidth - 9)
                                        .clamp(0, constraints.maxWidth - 18),
                                top:
                                    ((1 - _hsv.value) * constraints.maxHeight -
                                            9)
                                        .clamp(0, constraints.maxHeight - 18),
                                child: Container(
                                  width: 18,
                                  height: 18,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    color: _hsv.toColor(),
                                    border: Border.all(
                                      color: Colors.white,
                                      width: 2,
                                    ),
                                    boxShadow: const [
                                      BoxShadow(
                                        color: Colors.black,
                                        blurRadius: 2,
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                _slider(
                  'Hue',
                  _hsv.hue,
                  360,
                  (v) => _choose(_hsv.withHue(v)),
                  hue: true,
                ),
                _slider(
                  'Saturation',
                  _hsv.saturation * 100,
                  100,
                  (v) => _choose(_hsv.withSaturation(v / 100)),
                ),
                _slider(
                  'Brightness',
                  _hsv.value * 100,
                  100,
                  (v) => _choose(_hsv.withValue(v / 100)),
                ),
                const SizedBox(height: 8),
                TextFormField(
                  key: const ValueKey('hex-color'),
                  controller: _hex,
                  style: const TextStyle(
                    fontFamily: 'Geist Mono',
                    fontSize: 14,
                  ),
                  autocorrect: false,
                  enableSuggestions: false,
                  decoration: InputDecoration(
                    labelText: 'Hex color',
                    prefixIcon: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Container(
                        width: 22,
                        height: 22,
                        decoration: BoxDecoration(
                          color: _hsv.toColor(),
                          borderRadius: BorderRadius.circular(4),
                          border: Border.all(color: scheme.outline),
                        ),
                      ),
                    ),
                  ),
                  validator: (value) =>
                      RegExp(r'^#?[a-fA-F0-9]{6}$').hasMatch(value ?? '')
                      ? null
                      : 'Enter a six-digit hex color, such as #234E70.',
                  onChanged: (value) {
                    if (RegExp(r'^#?[a-fA-F0-9]{6}$').hasMatch(value)) {
                      _choose(
                        HSVColor.fromColor(
                          Color(
                            0xFF000000 |
                                int.parse(
                                  value.replaceFirst('#', ''),
                                  radix: 16,
                                ),
                          ),
                        ),
                        updateHex: false,
                      );
                    }
                  },
                ),
                const SizedBox(height: 16),
                if (widget.accentOnly)
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: _first,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      'Accent preview',
                      style: TextStyle(
                        color: colorContrast(_first, Colors.white) >= 4.5
                            ? Colors.white
                            : Colors.black,
                      ),
                    ),
                  )
                else ...[
                  Semantics(
                    label:
                        'Text preview. Contrast ${contrast.toStringAsFixed(2)} to one.',
                    child: Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: _first,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: scheme.outline),
                      ),
                      child: Text(
                        'JANITRA text preview',
                        style: TextStyle(color: _second),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Contrast ${contrast.toStringAsFixed(2)}:1. Minimum 4.5:1.',
                  ),
                ],
                if (_message != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: Semantics(
                      liveRegion: true,
                      child: Text(
                        _message!,
                        style: TextStyle(color: scheme.error),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton.icon(
          onPressed: () => Navigator.pop(context),
          icon: const Icon(Icons.close),
          label: const Text('Cancel'),
        ),
        FilledButton.icon(
          onPressed: () {
            if (!_form.currentState!.validate()) return;
            if (!widget.accentOnly && contrast < 4.5) {
              setState(
                () => _message =
                    'Choose more contrasting colors (at least 4.5:1).',
              );
              return;
            }
            Navigator.pop(context, (_first, _second));
          },
          icon: const Icon(Icons.check),
          label: const Text('Apply colors'),
        ),
      ],
    );
  }
}
