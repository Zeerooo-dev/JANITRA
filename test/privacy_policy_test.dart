import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/testing.dart';
import 'package:janitra/app.dart';
import 'package:janitra/core/appearance_settings.dart';
import 'package:janitra/core/app_theme.dart';
import 'package:janitra/core/aurora_glass.dart';
import 'package:janitra/features/authentication/login_page.dart';
import 'package:janitra/features/privacy/privacy_policy_page.dart';
import 'package:janitra/features/workspace/home_setup_panel.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'fixtures/workspace_backend.dart';

void main() {
  Future<void> settlePolicy(WidgetTester tester) async {
    // Asset reads use real file I/O in the Flutter test binding.
    for (var i = 0; i < 4; i++) {
      await tester.pump();
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
    }
    await tester.pumpAndSettle();
  }

  setUpAll(() async {
    await (FontLoader('Roboto')
          ..addFont(rootBundle.load('assets/fonts/Roboto-Regular.ttf'))
          ..addFont(rootBundle.load('assets/fonts/Roboto-Bold.ttf')))
        .load();
    await rootBundle.loadString('assets/privacy/policy.json');
    await (FontLoader(
      'MaterialIcons',
    )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
  });

  test('Bundled policy has complete dates, public contact and verified feature disclosures', () async {
    final raw = await rootBundle.loadString('assets/privacy/policy.json');
    final data = jsonDecode(raw) as Map<String, dynamic>;
    expect(data['operator'], 'Zeerooo-dev');
    expect(data['privacyEmail'], 'jeffirie12@gmail.com');
    expect(DateTime.tryParse(data['effectiveDate']), isNotNull);
    expect(DateTime.tryParse(data['updatedDate']), isNotNull);
    expect(raw, isNot(contains('[Date')));
    expect(raw, isNot(contains('[Legal')));
    for (final term in [
      'Company-Wide',
      'Tokyo',
      'Gmail',
      'GitHub',
      'eight hours',
      'not fully anonymize',
      'not automatically removed',
      'self-service',
    ]) {
      expect(raw, contains(term));
    }
  });

  for (final brightness in Brightness.values) {
    testWidgets(
      'Privacy works offline in $brightness at 320px and large text',
      (tester) async {
        tester.view.physicalSize = const Size(320, 640);
        tester.view.devicePixelRatio = 1;
        tester.platformDispatcher.textScaleFactorTestValue = 2;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
        await tester.pumpWidget(
          MaterialApp(
            theme: janitraTheme(brightness: brightness),
            home: const PrivacyPolicyPage(),
          ),
        );
        await settlePolicy(tester);
        expect(find.text('JANITRA Privacy Policy'), findsOneWidget);
        expect(
          find.textContaining('Effective date: 2026-10-27'),
          findsOneWidget,
        );
        expect(find.textContaining('jeffirie12@gmail.com'), findsOneWidget);
        await expectLater(
          find.byType(Scaffold),
          matchesGoldenFile(
            'goldens/privacy-${brightness.name}-large-text.png',
          ),
        );
        await tester.ensureVisible(find.text('11. Changes and contact'));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      'High contrast setup text uses the solid card foreground in $brightness',
      (tester) async {
        tester.view.physicalSize = const Size(390, 844);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final settings = AppearanceSettings()..highContrast = true;
        final theme = janitraTheme(brightness: brightness, highContrast: true);
        await tester.pumpWidget(
          AppearanceScope(
            settings: settings,
            child: MaterialApp(
              theme: theme,
              home: Scaffold(
                body: SingleChildScrollView(
                  child: HomeSetupPanel(
                    hasAgency: false,
                    hasClient: false,
                    hasWorkplace: false,
                    canAddAgency: true,
                    canManageAgency: false,
                    isAdmin: true,
                    onAddAgency: () {},
                    onAddClient: () {},
                    onAddWorkplace: () {},
                    onManageTeam: () {},
                    onRefreshAccess: () {},
                  ),
                ),
              ),
            ),
          ),
        );
        final heading = tester.widget<Text>(find.text('Set up your workspace'));
        final ink = heading.style!.color!;
        final panel = find.byKey(const ValueKey('home-setup-hero'));
        final decoration =
            tester
                    .widget<DecoratedBox>(
                      find
                          .descendant(
                            of: panel,
                            matching: find.byType(DecoratedBox),
                          )
                          .first,
                    )
                    .decoration
                as BoxDecoration;
        expect(colorContrast(ink, decoration.color!), greaterThanOrEqualTo(7));
        expect(find.byType(BackdropFilter), findsNothing);
        expect(find.byType(JanitraGlassPanel), findsWidgets);
        await expectLater(
          find.byType(Scaffold),
          matchesGoldenFile(
            'goldens/setup-high-contrast-${brightness.name}.png',
          ),
        );
        await tester.pumpWidget(const SizedBox());
        settings.dispose();
      },
    );
  }

  test('Colored bars keep readable text and selected icons in every appearance mode', () {
    for (final brightness in Brightness.values) {
      for (final contrast in [false, true]) {
        for (final accent in [janitraNavy, Colors.yellow, Colors.red]) {
          final theme = janitraTheme(
            brightness: brightness,
            accent: accent,
            highContrast: contrast,
          );
          final minimum = contrast ? 7.0 : 4.5;
          final bar = theme.appBarTheme.backgroundColor!;
          expect(bar, isNot(theme.scaffoldBackgroundColor));
          expect(
            colorContrast(theme.appBarTheme.foregroundColor!, bar),
            greaterThanOrEqualTo(minimum),
          );
          final nav = theme.navigationBarTheme;
          for (final selected in [false, true]) {
            final states = selected ? {WidgetState.selected} : <WidgetState>{};
            expect(
              colorContrast(
                nav.labelTextStyle!.resolve(states)!.color!,
                nav.backgroundColor!,
              ),
              greaterThanOrEqualTo(minimum),
            );
            expect(
              colorContrast(
                nav.iconTheme!.resolve(states)!.color!,
                selected ? nav.indicatorColor! : nav.backgroundColor!,
              ),
              greaterThanOrEqualTo(minimum),
            );
          }
        }
      }
    }
  });

  for (final role in ['signed out', 'admin', 'supervisor', 'personnel']) {
    testWidgets(
      '$role can read Privacy Policy and return without losing navigation',
      (tester) async {
        final backend = WorkspaceTestBackend()..addSite();
        if (role != 'signed out') {
          backend.roles = [
            {
              'role': role,
              'agency_id': role == 'admin' ? null : fixtureAgencyId,
              'site_id': role == 'admin' ? null : fixtureSiteId,
            },
          ];
        }
        final client = (await tester.runAsync(
          () async => SupabaseClient(
            'https://example.supabase.co',
            'sb_publishable_test',
            httpClient: MockClient(backend.handle),
            authOptions: const AuthClientOptions(autoRefreshToken: false),
          ),
        ))!;
        addTearDown(() async {
          await tester.pumpWidget(const SizedBox());
          await tester.runAsync(client.dispose);
        });
        if (role != 'signed out') {
          await tester.runAsync(
            () => client.auth.signInWithPassword(
              email: 'worker@example.test',
              password: 'test-session-only',
            ),
          );
        }
        await tester.pumpWidget(JanitraApp(client: client));
        await tester.pumpAndSettle();
        if (role == 'signed out') {
          await tester.enterText(
            find.byType(TextFormField).first,
            'keep@example.test',
          );
        } else {
          await tester.tap(find.byTooltip('Profile').first);
          await tester.pumpAndSettle();
          expect(find.text('Settings'), findsOneWidget);
        }
        await tester.ensureVisible(find.text('Privacy Policy'));
        await tester.tap(find.text('Privacy Policy'));
        await settlePolicy(tester);
        expect(find.byType(PrivacyPolicyPage), findsOneWidget);
        await tester.pageBack();
        await tester.pumpAndSettle();
        if (role == 'signed out') {
          expect(find.byType(LoginPage), findsOneWidget);
          expect(find.text('keep@example.test'), findsOneWidget);
        } else {
          expect(find.text('Settings'), findsOneWidget);
          expect(client.auth.currentUser, isNotNull);
        }
      },
    );
  }

  testWidgets(
    'Privacy remains available when backend initialization is unavailable',
    (tester) async {
      await tester.pumpWidget(const JanitraApp());
      await tester.pumpAndSettle();
      await tester.tap(find.text('Privacy Policy'));
      await settlePolicy(tester);
      expect(find.byType(PrivacyPolicyPage), findsOneWidget);
      expect(find.textContaining('Effective date: 2026-10-27'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    },
  );
}
