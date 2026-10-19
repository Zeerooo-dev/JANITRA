import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:janitra/core/app_theme.dart';
import 'package:janitra/core/startup_reveal.dart';
import 'package:janitra/features/workspace/account_code_page.dart';

void main() {
  setUpAll(() async {
    await (FontLoader('Roboto')
          ..addFont(rootBundle.load('assets/fonts/Roboto-Regular.ttf'))
          ..addFont(rootBundle.load('assets/fonts/Roboto-Bold.ttf')))
        .load();
    await (FontLoader(
      'MaterialIcons',
    )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
  });

  testWidgets(
    'startup reveal keeps the child mounted and does not replay on resume',
    (tester) async {
      final key = GlobalKey();
      var count = 0;
      await tester.pumpWidget(
        MaterialApp(
          theme: janitraTheme(),
          home: StartupReveal(
            child: StatefulBuilder(
              key: key,
              builder: (context, setState) => Scaffold(
                body: FilledButton(
                  onPressed: () => setState(() => count++),
                  child: Text('Workspace $count'),
                ),
              ),
            ),
          ),
        ),
      );
      final state = key.currentState;
      expect(state, isNotNull);
      final overlay = find.byKey(const ValueKey('startup-logo'));
      expect(overlay, findsOneWidget);
      expect(find.text('Workspace 0').hitTestable(), findsNothing);
      final scale = find.descendant(
        of: overlay,
        matching: find.byType(ScaleTransition),
      );
      final initial = tester.widget<ScaleTransition>(scale).scale.value;
      await tester.pump(const Duration(milliseconds: 300));
      expect(
        tester.widget<ScaleTransition>(scale).scale.value,
        greaterThan(initial),
      );
      await tester.pump(const Duration(milliseconds: 400));
      expect(overlay, findsNothing);
      expect(identical(key.currentState, state), isTrue);
      await tester.tap(find.text('Workspace 0'));
      await tester.pumpAndSettle();
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump(const Duration(seconds: 1));
      expect(overlay, findsNothing);
      expect(find.text('Workspace 1'), findsOneWidget);
      expect(identical(key.currentState, state), isTrue);
    },
  );

  for (final initiallyReduced in [true, false]) {
    testWidgets(
      'startup skips or immediately stops when Reduce motion is enabled ($initiallyReduced)',
      (tester) async {
        var reduced = initiallyReduced;
        late StateSetter update;
        await tester.pumpWidget(
          MaterialApp(
            home: StatefulBuilder(
              builder: (context, setState) {
                update = setState;
                return MediaQuery(
                  data: MediaQuery.of(context)
                      .copyWith(disableAnimations: reduced),
                  child: const StartupReveal(
                    child: Scaffold(body: Text('Ready')),
                  ),
                );
              },
            ),
          ),
        );
        if (!initiallyReduced) {
          await tester.pump(const Duration(milliseconds: 100));
          expect(find.byKey(const ValueKey('startup-logo')), findsOneWidget);
          update(() => reduced = true);
          await tester.pump();
        }
        expect(find.byKey(const ValueKey('startup-logo')), findsNothing);
        expect(find.text('Ready').hitTestable(), findsOneWidget);
        update(() => reduced = false);
        await tester.pumpAndSettle();
        expect(find.byKey(const ValueKey('startup-logo')), findsNothing);
      },
    );
  }

  Future<MaterialPageRoute<void>> openDetail(
    WidgetTester tester, {
    bool reduced = false,
  }) async {
    late MaterialPageRoute<void> route;
    await tester.pumpWidget(
      MaterialApp(
        theme: janitraTheme(),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(disableAnimations: reduced),
          child: child!,
        ),
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () {
                route = MaterialPageRoute<void>(
                  builder: (_) => const Scaffold(body: Text('Detail')),
                );
                Navigator.of(context).push(route);
              },
              child: const Text('Open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pump();
    return route;
  }

  testWidgets(
    'Android page transitions are quick and predictive back can cancel and commit',
    (tester) async {
      FocusManager.instance.highlightStrategy =
          FocusHighlightStrategy.alwaysTouch;
      addTearDown(
        () => FocusManager.instance.highlightStrategy =
            FocusHighlightStrategy.automatic,
      );
      final route = await openDetail(tester);
      expect(route.transitionDuration, const Duration(milliseconds: 220));
      expect(
        route.reverseTransitionDuration,
        const Duration(milliseconds: 180),
      );
      await tester.pumpAndSettle();
      Future<void> back(String method, [Map<String, dynamic>? data]) async {
        await tester.binding.defaultBinaryMessenger.handlePlatformMessage(
          'flutter/backgesture',
          const StandardMethodCodec().encodeMethodCall(
            MethodCall(method, data),
          ),
          (_) {},
        );
        await tester.pump();
      }

      final event = {
        'touchOffset': [5.0, 300.0],
        'progress': 0.0,
        'swipeEdge': 0,
      };
      await back('startBackGesture', event);
      await back('updateBackGestureProgress', {
        ...event,
        'touchOffset': [100.0, 300.0],
        'progress': 0.35,
      });
      expect(route.popGestureInProgress, isTrue);
      await back('cancelBackGesture');
      await tester.pumpAndSettle();
      expect(find.text('Detail'), findsOneWidget);
      await back('startBackGesture', event);
      await back('commitBackGesture');
      await tester.pumpAndSettle();
      expect(find.text('Detail'), findsNothing);
      expect(find.text('Open'), findsOneWidget);
    },
  );

  for (final keyboard in [true, false]) {
    testWidgets(
      '${keyboard ? 'Keyboard navigation' : 'Reduce motion'} skips page transition visuals',
      (tester) async {
        FocusManager.instance.highlightStrategy = keyboard
            ? FocusHighlightStrategy.alwaysTraditional
            : FocusHighlightStrategy.alwaysTouch;
        addTearDown(
          () => FocusManager.instance.highlightStrategy =
              FocusHighlightStrategy.automatic,
        );
        await openDetail(tester, reduced: !keyboard);
        await tester.pump(const Duration(milliseconds: 1));
        expect(find.text('Detail').hitTestable(), findsOneWidget);
        await tester.pumpAndSettle();
      },
    );
  }

  for (final reduced in [false, true]) {
    testWidgets(
      'copy confirmation respects motion and hides sensitive code on background ($reduced)',
      (tester) async {
        FocusManager.instance.highlightStrategy =
            FocusHighlightStrategy.alwaysTouch;
        addTearDown(
          () => FocusManager.instance.highlightStrategy =
              FocusHighlightStrategy.automatic,
        );
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.resumed,
        );
        tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          (_) async => null,
        );
        addTearDown(
          () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
            SystemChannels.platform,
            null,
          ),
        );
        await tester.pumpWidget(
          MaterialApp(
            theme: janitraTheme(),
            home: MediaQuery(
              data: MediaQueryData(disableAnimations: reduced),
              child: AccountCodePage(
                grant: {
                  'setup_code': 'a' * 43,
                  'identifier': 'test.person',
                  'expires_at': '2026-10-20T00:00:00Z',
                },
              ),
            ),
          ),
        );
        await tester.tap(find.byIcon(Icons.copy));
        await tester.pump();
        expect(find.byIcon(Icons.check), findsOneWidget);
        expect(find.text('Code copied'), findsOneWidget);
        if (reduced) expect(find.byType(AnimatedSwitcher), findsNothing);
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.inactive,
        );
        await tester.pump();
        expect(find.text('a' * 43), findsNothing);
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.resumed,
        );
        await tester.pumpAndSettle();
      },
    );
  }

  testWidgets(
    'startup logo uses JANITRA branding in dark mode with large text',
    (tester) async {
      tester.view.physicalSize = const Size(320, 720);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        MaterialApp(
          theme: janitraTheme(brightness: Brightness.dark),
          home: MediaQuery(
            data: const MediaQueryData(textScaler: TextScaler.linear(2)),
            child: const StartupReveal(child: Scaffold()),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 300));
      await expectLater(
        find.byType(StartupReveal),
        matchesGoldenFile('goldens/startup-logo-dark-large-text.png'),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    },
  );
}
