import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/testing.dart';
import 'package:janitra/app.dart';
import 'package:janitra/core/appearance_settings.dart';
import 'package:janitra/core/app_theme.dart';
import 'package:janitra/features/appearance/appearance_page.dart';
import 'package:janitra/features/about/about_page.dart';
import 'package:janitra/features/workspace/workspace_page.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'fixtures/workspace_backend.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    await (FontLoader('Roboto')
          ..addFont(rootBundle.load('assets/fonts/Roboto-Regular.ttf'))
          ..addFont(rootBundle.load('assets/fonts/Roboto-Bold.ttf')))
        .load();
    await (FontLoader(
      'MaterialIcons',
    )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
  });
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));

  test('preferences survive reopening and rapid saves; reset keeps session storage', () async {
    final storage = <String, String>{
      'janitra.test.session': 'test-session-only',
    };
    FlutterSecureStorage.setMockInitialValues(storage);
    final settings = AppearanceSettings();
    addTearDown(settings.dispose);
    await Future.wait([
      settings.update(mode: ThemeMode.dark, accent: const Color(0xFF0066CC)),
      settings.update(font: 'system', textScale: 1.4),
      settings.update(highContrast: true, motion: MotionPreference.on),
    ]);
    await settings.setColors(Brightness.light, Colors.white, Colors.black);
    await settings.setColors(Brightness.dark, Colors.black, Colors.white);
    final restored = AppearanceSettings();
    addTearDown(restored.dispose);
    await restored.load();
    expect(restored.mode, ThemeMode.dark);
    expect(restored.accent, const Color(0xFF0066CC));
    expect(restored.font, 'system');
    expect(restored.textScale, 1.4);
    expect(restored.highContrast, isTrue);
    expect(restored.motion, MotionPreference.on);
    expect(restored.backgroundFor(Brightness.dark), Colors.black);
    expect(restored.backgroundFor(Brightness.light), Colors.white);
    await restored.reset();
    final reset = AppearanceSettings();
    addTearDown(reset.dispose);
    await reset.load();
    expect(reset.mode, ThemeMode.system);
    expect(reset.font, 'Roboto');
    expect(reset.accent, janitraNavy);
    expect(reset.textScale, 1);
    expect(reset.backgroundFor(Brightness.dark), isNull);
    expect(storage['janitra.test.session'], 'test-session-only');
  });

  test('corrupt and invalid saved settings cannot break appearance', () async {
    FlutterSecureStorage.setMockInitialValues({
      AppearanceSettings.storageKey: '{broken',
    });
    final broken = AppearanceSettings();
    addTearDown(broken.dispose);
    await broken.load();
    expect(broken.mode, ThemeMode.system);
    expect(broken.error, isNotNull);
    FlutterSecureStorage.setMockInitialValues({
      AppearanceSettings.storageKey: jsonEncode({
        'mode': 'unknown',
        'motion': {},
        'accent': -1,
        'font': 'missing-font',
        'textScale': 999,
        'colors': {
          'dark': {'background': 0xFFFFFFFF, 'foreground': 0xFFFFFFFF},
        },
      }),
    });
    final invalid = AppearanceSettings();
    addTearDown(invalid.dispose);
    await invalid.load();
    expect(invalid.mode, ThemeMode.system);
    expect(invalid.motion, MotionPreference.system);
    expect(invalid.accent, janitraNavy);
    expect(invalid.textScale, 1);
    expect(invalid.font, 'Roboto');
    expect(invalid.backgroundFor(Brightness.dark), isNull);
    expect(() => invalid.update(textScale: double.nan), throwsArgumentError);
    expect(() => invalid.update(font: 'missing-font'), throwsArgumentError);
    expect(
      () => invalid.setColors(Brightness.light, Colors.white, Colors.white),
      throwsArgumentError,
    );
  });

  test('storage failure is reported and a later save can recover', () async {
    FlutterSecureStorage.setMockInitialValues(
      Map.unmodifiable(<String, String>{}),
    );
    final settings = AppearanceSettings();
    addTearDown(settings.dispose);
    await settings.update(mode: ThemeMode.dark);
    expect(settings.mode, ThemeMode.dark);
    expect(settings.error, contains('could not be saved'));
    FlutterSecureStorage.setMockInitialValues({});
    await settings.update(mode: ThemeMode.light);
    expect(settings.error, isNull);
    final reopened = AppearanceSettings();
    addTearDown(reopened.dispose);
    await reopened.load();
    expect(reopened.mode, ThemeMode.light);
  });

  test(
    'every bundled font loads with regular and bold faces and persists',
    () async {
      for (final family in AppearanceSettings.fonts.where(
        (f) => f != 'system',
      )) {
        final stem = family.replaceAll(' ', '');
        final loader = FontLoader(family);
        for (final weight in ['Regular', 'Bold']) {
          final data = await rootBundle.load('assets/fonts/$stem-$weight.ttf');
          expect(data.lengthInBytes, greaterThan(1000));
          loader.addFont(Future.value(data));
        }
        await loader.load();
        final settings = AppearanceSettings();
        await settings.update(font: family);
        final restored = AppearanceSettings();
        await restored.load();
        expect(restored.font, family);
        expect(
          janitraTheme(font: family).textTheme.bodyMedium!.fontFamily,
          family,
        );
        settings.dispose();
        restored.dispose();
      }
    },
  );

  test(
    'preset and extreme custom accents keep light and dark text readable',
    () {
      for (final brightness in Brightness.values) {
        for (final accent in [
          ...AppearancePage.accents.values,
          Colors.white,
          Colors.black,
          Colors.yellow,
        ]) {
          for (final high in [false, true]) {
            for (final background in [null, Colors.black, Colors.white]) {
              final theme = janitraTheme(
                brightness: brightness,
                accent: accent,
                background: background,
                foreground: background == Colors.black ? Colors.white : null,
                highContrast: high,
              );
              final scheme = theme.colorScheme;
              expect(
                colorContrast(scheme.onSurface, scheme.surface),
                greaterThanOrEqualTo(high ? 7 : 4.5),
              );
              expect(
                colorContrast(scheme.onSurfaceVariant, scheme.surface),
                greaterThanOrEqualTo(high ? 7 : 4.5),
              );
              expect(
                colorContrast(scheme.primary, scheme.surface),
                greaterThanOrEqualTo(high ? 7 : 4.5),
              );
              expect(
                colorContrast(scheme.onPrimary, scheme.primary),
                greaterThanOrEqualTo(4.5),
              );
              expect(
                colorContrast(scheme.error, scheme.surface),
                greaterThanOrEqualTo(4.5),
              );
              expect(
                colorContrast(scheme.onError, scheme.error),
                greaterThanOrEqualTo(4.5),
              );
              expect(
                colorContrast(
                  scheme.onPrimaryContainer,
                  scheme.primaryContainer,
                ),
                greaterThanOrEqualTo(4.5),
              );
            }
          }
        }
      }
    },
  );

  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 4; i++) {
      await tester.pump();
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 40)),
      );
    }
    await tester.pumpAndSettle();
  }

  Future<AppearanceSettings> open(
    WidgetTester tester, {
    bool signedIn = true,
    bool personnel = false,
    double width = 390,
    double scale = 1,
    bool freezeAmbient = false,
  }) async {
    tester.view.physicalSize = Size(width, 844);
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = scale;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    final backend = WorkspaceTestBackend()..addSite();
    if (personnel) {
      backend.roles = [
        {
          'role': 'personnel',
          'agency_id': fixtureAgencyId,
          'site_id': fixtureSiteId,
        },
      ];
    }
    final client = (await tester.runAsync(
      () async => SupabaseClient(
        'https://example.supabase.co',
        'test',
        httpClient: MockClient(backend.handle),
        authOptions: const AuthClientOptions(autoRefreshToken: false),
      ),
    ))!;
    final settings = AppearanceSettings();
    if (freezeAmbient) settings.motion = MotionPreference.off;
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox());
      await tester.runAsync(client.dispose);
      settings.dispose();
    });
    if (signedIn) {
      await tester.runAsync(
        () => client.auth.signInWithPassword(
          email: 'test@example.test',
          password: 'test-only',
        ),
      );
    }
    await tester.pumpWidget(JanitraApp(client: client, appearance: settings));
    await settle(tester);
    return settings;
  }

  Future<void> tap(WidgetTester tester, Finder finder) async {
    await tester.scrollUntilVisible(
      finder,
      250,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    await tester.tap(finder);
    await settle(tester);
  }

  Future<void> openAppearance(WidgetTester tester) async {
    await tester.tap(find.byTooltip('Profile').first);
    await settle(tester);
    await tap(tester, find.text('Appearance'));
  }

  Future<void> enterHex(WidgetTester tester, String value) async {
    final field = find.byKey(const ValueKey('hex-color'));
    await tester.ensureVisible(field);
    await tester.pumpAndSettle();
    await tester.enterText(field, value);
    await settle(tester);
  }

  testWidgets('Profile appearance controls apply immediately and reset', (
    tester,
  ) async {
    final settings = await open(tester);
    await openAppearance(tester);
    await tap(tester, find.widgetWithText(ChoiceChip, 'Dark'));
    expect(
      Theme.of(tester.element(find.byType(AppearancePage))).brightness,
      Brightness.dark,
    );
    await tap(tester, find.widgetWithText(ChoiceChip, 'Forest'));
    expect(settings.accent, AppearancePage.accents['Forest']);
    await tap(tester, find.byType(DropdownButtonFormField<String>));
    await tester.tap(find.text('System font').last);
    await settle(tester);
    expect(settings.font, 'system');
    await tap(tester, find.byType(Slider));
    expect(settings.textScale, greaterThan(1));
    await tap(tester, find.byType(SwitchListTile));
    expect(settings.highContrast, isTrue);
    await tap(tester, find.byType(DropdownButtonFormField<MotionPreference>));
    await tester.tap(find.text('On').last);
    await settle(tester);
    expect(settings.motion, MotionPreference.on);
    expect(
      MediaQuery.disableAnimationsOf(
        tester.element(find.byType(AppearancePage)),
      ),
      isTrue,
    );
    await tap(tester, find.text('Reset to default'));
    expect(settings.mode, ThemeMode.system);
    expect(settings.accent, janitraNavy);
    expect(settings.font, 'Roboto');
    expect(settings.textScale, 1);
    expect(settings.highContrast, isFalse);
    expect(settings.motion, MotionPreference.system);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'color editor validates contrast, applies safe colors and cancels cleanly',
    (tester) async {
      final settings = await open(tester);
      await openAppearance(tester);
      await tap(tester, find.text('Background and text'));
      await enterHex(tester, 'nope');
      await tester.tap(find.text('Apply colors'));
      await settle(tester);
      expect(find.textContaining('six-digit hex'), findsOneWidget);
      await enterHex(tester, '#FFFFFF');
      await tap(tester, find.textContaining(RegExp(r'^Text #')));
      await enterHex(tester, '#FFFFFF');
      await tester.tap(find.text('Apply colors'));
      await settle(tester);
      expect(find.textContaining('at least 4.5:1'), findsOneWidget);
      await enterHex(tester, '#202C39');
      await tester.tap(find.text('Apply colors'));
      await settle(tester);
      expect(settings.backgroundFor(Brightness.light), Colors.white);
      await tap(tester, find.text('Custom accent'));
      await enterHex(tester, '#006EFE');
      await tester.tap(find.text('Apply colors'));
      await settle(tester);
      expect(settings.accent, const Color(0xFF006EFE));
      await tap(tester, find.text('Custom accent'));
      await enterHex(tester, '#FF0000');
      await tester.tap(find.text('Cancel'));
      await settle(tester);
      expect(settings.accent, const Color(0xFF006EFE));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'system mode follows phone brightness and preserves sign-in input',
    (tester) async {
      final settings = await open(tester, signedIn: false);
      addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
      await tester.enterText(find.byType(TextFormField).first, 'my-personnel');
      await tester.enterText(
        find.byType(TextFormField).last,
        'test-only-password',
      );
      tester.platformDispatcher.platformBrightnessTestValue = Brightness.dark;
      await settle(tester);
      expect(
        Theme.of(tester.element(find.byType(Scaffold))).brightness,
        Brightness.dark,
      );
      expect(
        tester
            .widget<EditableText>(find.byType(EditableText).first)
            .controller
            .text,
        'my-personnel',
      );
      await tester.runAsync(() => settings.update(mode: ThemeMode.light));
      await settle(tester);
      expect(
        Theme.of(tester.element(find.byType(Scaffold))).brightness,
        Brightness.light,
      );
      expect(
        tester
            .widget<EditableText>(find.byType(EditableText).last)
            .controller
            .text,
        'test-only-password',
      );
    },
  );

  testWidgets('color area and sliders update hex without saving before Apply', (
    tester,
  ) async {
    final settings = await open(tester);
    await openAppearance(tester);
    await tap(tester, find.text('Custom accent'));
    final area = find.byKey(const ValueKey('color-area'));
    await tester.ensureVisible(area);
    await tester.pumpAndSettle();
    final rect = tester.getRect(area);
    await tester.tapAt(
      rect.topLeft + Offset(rect.width * .8, rect.height * .25),
    );
    await settle(tester);
    String hexValue() => tester
        .widget<TextFormField>(find.byKey(const ValueKey('hex-color')))
        .controller!
        .text;
    final chosen = hexValue();
    expect(chosen, isNot('#234E70'));
    expect(settings.accent, janitraNavy);
    for (final name in ['Hue', 'Saturation', 'Brightness']) {
      final slider = find.byKey(ValueKey(name));
      await tester.ensureVisible(slider);
      await tester.pumpAndSettle();
      await tester.tapAt(tester.getCenter(slider));
      await settle(tester);
      expect(hexValue(), matches(RegExp(r'^#[0-9A-F]{6}$')));
    }
    expect(hexValue(), isNot(chosen));
    final expected = Color(
      0xFF000000 | int.parse(hexValue().substring(1), radix: 16),
    );
    await tester.tap(find.text('Apply colors'));
    await settle(tester);
    expect(settings.accent, expected);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'visual picker fits a narrow phone at large text and cancels safely',
    (tester) async {
      final settings = await open(tester, width: 320, scale: 2);
      await openAppearance(tester);
      await tester.runAsync(() => settings.update(textScale: 1.4));
      await settle(tester);
      await tap(tester, find.text('Background and text'));
      await enterHex(tester, '#000000');
      await tap(tester, find.textContaining(RegExp(r'^Text #')));
      await enterHex(tester, '#FFFFFF');
      await tester.tap(find.text('Cancel'));
      await settle(tester);
      expect(settings.backgroundFor(Brightness.light), isNull);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('visual color picker renders in light and dark mode', (
    tester,
  ) async {
    final settings = await open(tester);
    await openAppearance(tester);
    for (final mode in [ThemeMode.light, ThemeMode.dark]) {
      await tester.runAsync(() => settings.update(mode: mode));
      await settle(tester);
      await tap(tester, find.text('Custom accent'));
      await expectLater(
        find.byType(AlertDialog),
        matchesGoldenFile('goldens/color-picker-${mode.name}.png'),
      );
      await tester.tap(find.text('Cancel'));
      await settle(tester);
      await tap(tester, find.text('Background and text'));
      await expectLater(
        find.byType(AlertDialog),
        matchesGoldenFile('goldens/color-pair-${mode.name}.png'),
      );
      await tester.tap(find.text('Cancel'));
      await settle(tester);
    }
  });

  testWidgets('reduce motion follows the phone and explicit overrides', (
    tester,
  ) async {
    final settings = await open(tester);
    addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
    tester.platformDispatcher.accessibilityFeaturesTestValue =
        const FakeAccessibilityFeatures(disableAnimations: true);
    await settle(tester);
    bool reduced() =>
        MediaQuery.disableAnimationsOf(tester.element(find.byType(Scaffold)));
    expect(reduced(), isTrue);
    expect(
      tester
          .widget<NavigationBar>(find.byType(NavigationBar))
          .animationDuration,
      Duration.zero,
    );
    await tester.runAsync(() => settings.update(motion: MotionPreference.off));
    await settle(tester);
    expect(reduced(), isFalse);
    await tester.runAsync(() => settings.update(motion: MotionPreference.on));
    await settle(tester);
    expect(reduced(), isTrue);
    expect(
      tester
          .widget<NavigationBar>(find.byType(NavigationBar))
          .animationDuration,
      Duration.zero,
    );
    expect(
      tester
          .widget<MaterialApp>(find.byType(MaterialApp))
          .themeAnimationDuration,
      Duration.zero,
    );
  });

  for (final personnel in [false, true]) {
    testWidgets(
      '${personnel ? 'Personnel' : 'Supervisor'} retains Profile and navigation when appearance changes',
      (tester) async {
        final settings = await open(
          tester,
          signedIn: true,
          personnel: personnel,
        );
        final workspace = tester.state(find.byType(WorkspacePage));
        await tester.tap(find.byTooltip('Profile').first);
        await settle(tester);
        for (final (label, icon) in [
          ('Appearance', Icons.palette_outlined),
          ('About JANITRA', Icons.info_outline),
          ('Two-Step Verification', Icons.shield_outlined),
          ('Edit Your Name', Icons.edit_outlined),
          ('Notifications', Icons.notifications_outlined),
          ('My Agency History', Icons.history_outlined),
          ('Refresh Workplace Access', Icons.refresh),
          ('Sign Out', Icons.logout),
          if (personnel) ...[
            ('Saved Offline Work', Icons.offline_pin_outlined),
            ('My Work Schedule', Icons.calendar_month_outlined),
          ] else
            ('Manage Your Supervisor PIN', Icons.pin_outlined),
        ]) {
          final control = find
              .ancestor(
                of: find.text(label),
                matching: find.byWidgetPredicate(
                  (w) => w is ListTile || w is ButtonStyleButton,
                ),
              )
              .first;
          expect(
            find.descendant(of: control, matching: find.byIcon(icon)),
            findsOneWidget,
          );
        }
        await tap(tester, find.text('About JANITRA'));
        expect(find.byType(AboutPage), findsOneWidget);
        await tester.pageBack();
        await settle(tester);
        expect(tester.state(find.byType(WorkspacePage)), same(workspace));
        await tap(tester, find.text('Appearance'));
        await tap(tester, find.widgetWithText(ChoiceChip, 'Dark'));
        await tester.runAsync(
          () => settings.update(textScale: 1.2, font: 'system'),
        );
        await settle(tester);
        await tester.pageBack();
        await settle(tester);
        expect(tester.state(find.byType(WorkspacePage)), same(workspace));
        expect(find.text('Your account'), findsOneWidget);
        expect(find.text('Workspace access pending'), findsNothing);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'appearance reflows at 320px with 200 percent system text and 140 percent app text',
    (tester) async {
      final settings = await open(tester, width: 320, scale: 2);
      await openAppearance(tester);
      await tester.runAsync(
        () => settings.update(
          mode: ThemeMode.dark,
          textScale: 1.4,
          font: 'Atkinson Hyperlegible',
        ),
      );
      await settle(tester);
      await expectLater(
        find.byType(Scaffold).last,
        matchesGoldenFile('goldens/appearance-large-text.png'),
      );
      await tap(tester, find.byType(DropdownButtonFormField<MotionPreference>));
      await tester.tap(find.text('On').last);
      await settle(tester);
      expect(tester.takeException(), isNull);
      await tap(tester, find.text('Reset to default'));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('Appearance renders in both modes', (tester) async {
    final settings = await open(tester);
    await openAppearance(tester);
    await tester.runAsync(
      () => precacheImage(
        const AssetImage('assets/icons/janitra_launcher_1024.png'),
        tester.element(find.byType(AppearancePage)),
      ),
    );
    await tester.pumpAndSettle();
    await expectLater(
      find.byType(Scaffold).last,
      matchesGoldenFile('goldens/appearance-light.png'),
    );
    await tap(tester, find.widgetWithText(ChoiceChip, 'Dark'));
    tester
        .state<ScrollableState>(find.byType(Scrollable).first)
        .position
        .jumpTo(0);
    await tester.pumpAndSettle();
    await expectLater(
      find.byType(Scaffold).last,
      matchesGoldenFile('goldens/appearance-dark.png'),
    );
    expect(tester.takeException(), isNull);
    expect(settings.mode, ThemeMode.dark);
  });

  for (final personnel in [false, true]) {
    testWidgets(
      'dark ${personnel ? 'Personnel' : 'Supervisor'} screens render with themed controls',
      (tester) async {
        final settings = await open(
          tester,
          signedIn: true,
          personnel: personnel,
          freezeAmbient: true,
        );
        await tester.runAsync(
          () => settings.update(
            mode: ThemeMode.dark,
            motion: MotionPreference.off,
          ),
        );
        await settle(tester);
        final role = personnel ? 'personnel' : 'supervisor';
        await expectLater(
          find.byType(Scaffold).first,
          matchesGoldenFile('goldens/dark-$role-home.png'),
        );
        for (final tab
            in personnel
                ? ['My Tasks', 'Profile']
                : ['Tasks', 'Team', 'Reports']) {
          await tester.tap(
            find.descendant(
              of: find.byType(NavigationBar),
              matching: find.text(tab),
            ),
          );
          await settle(tester);
          await expectLater(
            find.byType(Scaffold).first,
            matchesGoldenFile(
              'goldens/dark-$role-${tab.toLowerCase().replaceAll(' ', '-')}.png',
            ),
          );
          expect(tester.takeException(), isNull);
        }
      },
    );
  }
}
