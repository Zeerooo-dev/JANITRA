import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:janitra/core/ambient_background.dart';
import 'package:janitra/core/appearance_settings.dart';
import 'package:janitra/core/app_theme.dart';

void main() {
  Future<void> mount(
    WidgetTester tester,
    AppearanceSettings settings, {
    Brightness brightness = Brightness.dark,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: janitraTheme(brightness: brightness),
        home: AppearanceScope(
          settings: settings,
          child: const Scaffold(
            body: JanitraAmbientBackground(child: Center(child: Text('Home'))),
          ),
        ),
      ),
    );
  }

  testWidgets('Dark appearance draws a gradient behind accessible content', (
    tester,
  ) async {
    await mount(tester, AppearanceSettings());
    final background = tester.widget<DecoratedBox>(
      find.byKey(const ValueKey('janitra-ambient-gradient')),
    );
    expect(
      (background.decoration as BoxDecoration).gradient,
      isA<LinearGradient>(),
    );
    expect(find.text('Home'), findsOneWidget);
  });

  testWidgets('Light appearance also uses theme-derived colors', (
    tester,
  ) async {
    await mount(tester, AppearanceSettings(), brightness: Brightness.light);
    final background = tester.widget<DecoratedBox>(
      find.byKey(const ValueKey('janitra-ambient-gradient')),
    );
    final stops =
        (background.decoration as BoxDecoration).gradient as LinearGradient;
    expect(stops.colors, hasLength(3));
    expect(stops.colors[0], isNot(stops.colors[2]));
    expect(find.text('Home'), findsOneWidget);
  });

  testWidgets('High contrast preserves a flat custom background', (
    tester,
  ) async {
    final settings = AppearanceSettings()..highContrast = true;
    await mount(tester, settings);
    expect(
      find.byKey(const ValueKey('janitra-ambient-gradient')),
      findsNothing,
    );
    expect(find.byKey(const ValueKey('janitra-ambient-flat')), findsOneWidget);
    expect(find.text('Home'), findsOneWidget);
  });
}
