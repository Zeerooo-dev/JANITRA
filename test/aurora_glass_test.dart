import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:janitra/core/appearance_settings.dart';
import 'package:janitra/core/app_theme.dart';
import 'package:janitra/core/aurora_glass.dart';

void main() {
  testWidgets(
    'Aurora pauses on background and resumes without replacing content',
    (tester) async {
      final contentKey = GlobalKey();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: JanitraAuroraBackground(
              child: StatefulBuilder(
                key: contentKey,
                builder: (_, _) => const Text('Ready'),
              ),
            ),
          ),
        ),
      );
      final state = contentKey.currentState;
      final painter = tester
          .widget<CustomPaint>(
            find.byKey(const ValueKey('janitra-aurora-painter')),
          )
          .painter!;
      var frames = 0;
      void painted() => frames++;
      painter.addListener(painted);
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 10)),
      );
      await tester.pump(const Duration(milliseconds: 300));
      expect(frames, greaterThan(0));
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      final pausedFrames = frames;
      await tester.pump(const Duration(seconds: 1));
      expect(frames, pausedFrames);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 10)),
      );
      await tester.pump(const Duration(milliseconds: 300));
      expect(frames, greaterThan(pausedFrames));
      expect(contentKey.currentState, same(state));
      painter.removeListener(painted);
      await tester.pumpWidget(const SizedBox());
    },
  );

  for (final useSystemSetting in [false, true]) {
    testWidgets(
      'Aurora never repaints with motion disabled (system: $useSystemSetting)',
      (tester) async {
        final settings = AppearanceSettings()
          ..motion = useSystemSetting
              ? MotionPreference.system
              : MotionPreference.off;
        await tester.pumpWidget(
          AppearanceScope(
            settings: settings,
            child: MaterialApp(
              home: Scaffold(
                body: MediaQuery(
                  data: MediaQueryData(disableAnimations: useSystemSetting),
                  child: const JanitraAuroraBackground(child: Text('Ready')),
                ),
              ),
            ),
          ),
        );
        final painter = tester
            .widget<CustomPaint>(
              find.byKey(const ValueKey('janitra-aurora-painter')),
            )
            .painter!;
        var frames = 0;
        void painted() => frames++;
        painter.addListener(painted);
        await tester.pump(const Duration(seconds: 2));
        expect(frames, 0);
        painter.removeListener(painted);
        await tester.pumpWidget(const SizedBox());
        settings.dispose();
      },
    );
  }

  testWidgets('Aurora paints below content without consuming taps', (
    tester,
  ) async {
    var taps = 0;
    await tester.pumpWidget(
      MaterialApp(
        theme: janitraTheme(brightness: Brightness.dark),
        home: Scaffold(
          body: JanitraAuroraBackground(
            child: Center(
              child: JanitraGlassCard(
                child: TextButton(
                  onPressed: () => taps++,
                  child: const Text('Open task'),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    expect(
      find.byKey(const ValueKey('janitra-aurora-background')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('janitra-aurora-painter')),
      findsOneWidget,
    );
    expect(find.byType(BackdropFilter), findsWidgets);
    await tester.tap(find.text('Open task'));
    expect(taps, 1);
    // A running aurora must not leave an infinite animation ticker.
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('High contrast keeps a solid surface without blur', (
    tester,
  ) async {
    final settings = AppearanceSettings()..highContrast = true;
    await tester.pumpWidget(
      AppearanceScope(
        settings: settings,
        child: MaterialApp(
          theme: janitraTheme(brightness: Brightness.dark, highContrast: true),
          home: Scaffold(
            body: JanitraAuroraBackground(
              child: const JanitraGlassPanel(
                padding: EdgeInsets.all(12),
                child: Text('Readable'),
              ),
            ),
          ),
        ),
      ),
    );
    expect(find.byKey(const ValueKey('janitra-aurora-flat')), findsOneWidget);
    expect(find.byKey(const ValueKey('janitra-aurora-painter')), findsNothing);
    expect(find.byType(BackdropFilter), findsNothing);
    expect(find.text('Readable'), findsOneWidget);
    await tester.pumpAndSettle();
  });

  testWidgets('Motion off and OS reduced motion keep content accessible', (
    tester,
  ) async {
    final settings = AppearanceSettings()..motion = MotionPreference.off;
    await tester.pumpWidget(
      AppearanceScope(
        settings: settings,
        child: MaterialApp(
          theme: janitraTheme(),
          home: const Scaffold(
            body: MediaQuery(
              data: MediaQueryData(disableAnimations: true),
              child: JanitraAuroraBackground(
                child: Center(child: Text('Manage team')),
              ),
            ),
          ),
        ),
      ),
    );
    expect(find.text('Manage team'), findsOneWidget);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
