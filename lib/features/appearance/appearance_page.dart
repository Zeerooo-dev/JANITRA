import 'package:flutter/material.dart';

import '../../core/appearance_settings.dart';
import '../../core/app_theme.dart';
import 'color_picker_dialog.dart';

class AppearancePage extends StatelessWidget {
  const AppearancePage({super.key});
  static const accents = <String, Color>{
    'JANITRA': janitraNavy,
    'Ocean': Color(0xFF0066CC),
    'Forest': Color(0xFF23704C),
    'Plum': Color(0xFF7850A0),
    'Copper': Color(0xFF9C4D20),
  };

  Future<void> _editColors(
    BuildContext context, {
    bool accentOnly = false,
  }) async {
    final settings = AppearanceScope.of(context);
    final theme = Theme.of(context);
    final brightness = theme.brightness;
    final result = await showDialog<(Color, Color)>(
      context: context,
      builder: (_) => ColorPickerDialog(
        first: accentOnly
            ? settings.accent
            : settings.backgroundFor(brightness) ??
                  theme.scaffoldBackgroundColor,
        second:
            settings.foregroundFor(brightness) ?? theme.colorScheme.onSurface,
        accentOnly: accentOnly,
        brightness: brightness,
      ),
    );
    if (result != null) {
      if (accentOnly) {
        await settings.update(accent: result.$1);
      } else {
        await settings.setColors(brightness, result.$1, result.$2);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final settings = AppearanceScope.of(context);
    final theme = Theme.of(context), scheme = theme.colorScheme;
    Widget section(String title, List<Widget> children) => Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 20, bottom: 10),
          child: Text(title, style: theme.textTheme.titleMedium),
        ),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: children,
            ),
          ),
        ),
      ],
    );
    return Scaffold(
      appBar: AppBar(title: const Text('Appearance')),
      body: SafeArea(
        child: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 640),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
              children: [
                const Text(
                  'Make JANITRA comfortable to use. Changes apply immediately and are saved on this device.',
                ),
                section('Visual style', [
                  Text('Mode', style: theme.textTheme.labelLarge),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final (mode, label, icon) in [
                        (
                          ThemeMode.system,
                          'System',
                          Icons.brightness_auto_outlined,
                        ),
                        (ThemeMode.light, 'Light', Icons.light_mode_outlined),
                        (ThemeMode.dark, 'Dark', Icons.dark_mode_outlined),
                      ])
                        ChoiceChip(
                          label: Text(label),
                          avatar: Icon(icon, size: 18),
                          selected: settings.mode == mode,
                          onSelected: (_) => settings.update(mode: mode),
                        ),
                    ],
                  ),
                  const Divider(height: 28),
                  Text('Accent', style: theme.textTheme.labelLarge),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final entry in accents.entries)
                        ChoiceChip(
                          label: Text(entry.key),
                          avatar: Icon(
                            Icons.circle,
                            color: entry.value,
                            size: 16,
                          ),
                          selected: settings.accent == entry.value,
                          onSelected: (_) =>
                              settings.update(accent: entry.value),
                        ),
                      ActionChip(
                        label: const Text('Custom accent'),
                        onPressed: () => _editColors(context, accentOnly: true),
                      ),
                    ],
                  ),
                  const Divider(height: 28),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Background and text'),
                    subtitle: Text(
                      'Customize ${theme.brightness == Brightness.dark ? 'dark' : 'light'} mode colors',
                    ),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => _editColors(context),
                  ),
                ]),
                section('Preview', [
                  Row(
                    children: [
                      const JanitraLogo(size: 40),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          'Your work, clearly organized',
                          style: theme.textTheme.titleMedium,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  const Text('Schedules and tasks use your chosen appearance.'),
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: scheme.primaryContainer,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      'Accent preview',
                      style: TextStyle(color: scheme.onPrimaryContainer),
                    ),
                  ),
                ]),
                section('Text and accessibility', [
                  DropdownButtonFormField<String>(
                    key: ValueKey(settings.font),
                    isExpanded: true,
                    itemHeight: null,
                    initialValue: settings.font,
                    decoration: const InputDecoration(labelText: 'Font'),
                    selectedItemBuilder: (_) => [
                      for (final font in AppearanceSettings.fonts)
                        Text(
                          font == 'system' ? 'System font' : font,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontFamily: font == 'system' ? null : font,
                          ),
                        ),
                    ],
                    items: [
                      for (final font in AppearanceSettings.fonts)
                        DropdownMenuItem(
                          value: font,
                          child: Text(
                            font == 'system' ? 'System font' : font,
                            style: TextStyle(
                              fontFamily: font == 'system' ? null : font,
                            ),
                          ),
                        ),
                    ],
                    onChanged: (value) {
                      if (value != null) settings.update(font: value);
                    },
                  ),
                  const SizedBox(height: 18),
                  Text(
                    'Text size: ${(settings.textScale * 100).round()}%',
                    style: theme.textTheme.labelLarge,
                  ),
                  const Text('Adds to your phone’s text-size setting.'),
                  Slider(
                    value: settings.textScale,
                    min: 1,
                    max: 1.4,
                    divisions: 4,
                    label: '${(settings.textScale * 100).round()}%',
                    semanticFormatterCallback: (v) =>
                        '${(v * 100).round()} percent',
                    onChanged: (value) => settings.update(textScale: value),
                  ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Higher contrast'),
                    subtitle: const Text(
                      'Stronger text, borders and controls.',
                    ),
                    value: settings.highContrast,
                    onChanged: (value) => settings.update(highContrast: value),
                  ),
                  const SizedBox(height: 10),
                  DropdownButtonFormField<MotionPreference>(
                    key: ValueKey(settings.motion),
                    isExpanded: true,
                    itemHeight: null,
                    initialValue: settings.motion,
                    decoration: const InputDecoration(
                      labelText: 'Reduce motion',
                    ),
                    items: const [
                      DropdownMenuItem(
                        value: MotionPreference.system,
                        child: Text('Follow system'),
                      ),
                      DropdownMenuItem(
                        value: MotionPreference.on,
                        child: Text('On'),
                      ),
                      DropdownMenuItem(
                        value: MotionPreference.off,
                        child: Text('Off'),
                      ),
                    ],
                    onChanged: (value) {
                      if (value != null) settings.update(motion: value);
                    },
                  ),
                ]),
                if (settings.error != null)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    child: Semantics(
                      liveRegion: true,
                      child: Text(
                        settings.error!,
                        style: TextStyle(color: scheme.error),
                      ),
                    ),
                  ),
                const SizedBox(height: 16),
                OutlinedButton(
                  onPressed: settings.reset,
                  child: const Text('Reset to default'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
