import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

enum MotionPreference { system, on, off }

class AppearanceSettings extends ChangeNotifier {
  static const storageKey = 'janitra.appearance.v1';
  static const fonts = [
    'Roboto',
    'system',
    'Geist',
    'Geist Mono',
    'Inter',
    'Noto Sans',
    'Open Sans',
    'Poppins',
    'Atkinson Hyperlegible',
    'Lora',
  ];
  static const _storage = FlutterSecureStorage();
  ThemeMode mode = ThemeMode.system;
  MotionPreference motion = MotionPreference.system;
  Color accent = const Color(0xFF234E70);
  String font = 'Roboto';
  double textScale = 1;
  bool highContrast = false;
  final Map<String, Map<String, int>> _colors = {};
  Future<void> _writes = Future.value();
  String? error;
  bool _disposed = false;

  Color? backgroundFor(Brightness brightness) =>
      _color(brightness, 'background');
  Color? foregroundFor(Brightness brightness) =>
      _color(brightness, 'foreground');
  Color? _color(Brightness brightness, String name) {
    final value = _colors[brightness.name]?[name];
    return value == null ? null : Color(value);
  }

  Future<void> load() async {
    try {
      final raw = await _storage.read(key: storageKey);
      if (raw == null) return;
      final data = jsonDecode(raw) as Map<String, dynamic>;
      final savedMode = data['mode'];
      final savedMotion = data['motion'];
      mode = ThemeMode.values.firstWhere(
        (m) => m.name == savedMode,
        orElse: () => ThemeMode.system,
      );
      motion = MotionPreference.values.firstWhere(
        (m) => m.name == savedMotion,
        orElse: () => MotionPreference.system,
      );
      if (_validColor(data['accent'])) accent = Color(data['accent'] as int);
      if (fonts.contains(data['font'])) font = data['font'] as String;
      final scale = data['textScale'];
      if (scale is num && scale.isFinite && scale >= 1 && scale <= 1.4) {
        textScale = scale.toDouble();
      }
      highContrast = data['highContrast'] == true;
      final colors = data['colors'];
      if (colors is Map) {
        for (final brightness in Brightness.values) {
          final pair = colors[brightness.name];
          if (pair is Map &&
              _validColor(pair['background']) &&
              _validColor(pair['foreground']) &&
              colorContrast(
                    Color(pair['background'] as int),
                    Color(pair['foreground'] as int),
                  ) >=
                  4.5) {
            _colors[brightness.name] = {
              'background': pair['background'] as int,
              'foreground': pair['foreground'] as int,
            };
          }
        }
      }
    } catch (_) {
      error =
          'Could not restore appearance. You can choose your settings again.';
    }
    notifyListeners();
  }

  static bool _validColor(Object? value) =>
      value is int && value >= 0xFF000000 && value <= 0xFFFFFFFF;

  Future<void> update({
    ThemeMode? mode,
    MotionPreference? motion,
    Color? accent,
    String? font,
    double? textScale,
    bool? highContrast,
  }) {
    if (textScale != null &&
        (!textScale.isFinite || textScale < 1 || textScale > 1.4)) {
      throw ArgumentError.value(textScale, 'textScale');
    }
    if (font != null && !fonts.contains(font)) {
      throw ArgumentError.value(font, 'font');
    }
    if (mode != null) this.mode = mode;
    if (motion != null) this.motion = motion;
    if (accent != null) this.accent = accent.withValues(alpha: 1);
    if (font != null) this.font = font;
    if (textScale != null) this.textScale = textScale;
    if (highContrast != null) this.highContrast = highContrast;
    return _save();
  }

  Future<void> setColors(
    Brightness brightness,
    Color background,
    Color foreground,
  ) {
    if (colorContrast(background, foreground) < 4.5) {
      throw ArgumentError('Text and background need at least 4.5:1 contrast.');
    }
    _colors[brightness.name] = {
      'background': background.withValues(alpha: 1).toARGB32(),
      'foreground': foreground.withValues(alpha: 1).toARGB32(),
    };
    return _save();
  }

  Future<void> reset() {
    mode = ThemeMode.system;
    motion = MotionPreference.system;
    accent = const Color(0xFF234E70);
    font = 'Roboto';
    textScale = 1;
    highContrast = false;
    _colors.clear();
    return _save();
  }

  Future<void> _save() {
    error = null;
    final value = jsonEncode({
      'mode': mode.name,
      'motion': motion.name,
      'accent': accent.toARGB32(),
      'font': font,
      'textScale': textScale,
      'highContrast': highContrast,
      'colors': _colors,
    });
    if (!_disposed) notifyListeners();
    // Serialize writes so a slow older save cannot overwrite the latest choice.
    _writes = _writes.then((_) async {
      try {
        await _storage.write(key: storageKey, value: value);
        error = null;
      } catch (_) {
        error =
            'Appearance changed for now, but could not be saved. Try again.';
      }
      if (!_disposed) notifyListeners();
    });
    return _writes;
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}

double colorContrast(Color a, Color b) {
  final x = a.computeLuminance(), y = b.computeLuminance();
  return x > y ? (x + .05) / (y + .05) : (y + .05) / (x + .05);
}

class AppearanceScope extends InheritedNotifier<AppearanceSettings> {
  const AppearanceScope({
    super.key,
    required AppearanceSettings settings,
    required super.child,
  }) : super(notifier: settings);

  static AppearanceSettings of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<AppearanceScope>()!.notifier!;
}

class AppearanceTextScaler extends TextScaler {
  const AppearanceTextScaler(this.system, this.factor);
  final TextScaler system;
  final double factor;
  @override
  double scale(double fontSize) => system.scale(fontSize) * factor;
  @override
  double get textScaleFactor => scale(14) / 14;
  @override
  bool operator ==(Object other) =>
      other is AppearanceTextScaler &&
      other.system == system &&
      other.factor == factor;
  @override
  int get hashCode => Object.hash(system, factor);
}
