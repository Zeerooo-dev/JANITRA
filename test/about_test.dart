import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:janitra/core/app_theme.dart';
import 'package:janitra/features/about/about_page.dart';
import 'package:janitra/features/updates/apk_updater.dart';

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
    final data = await rootBundle.load('NOTICES.Z');
    final notices = utf8.decode(gzip.decode(data.buffer.asUint8List()));
    final entries = notices.split('\n${'-' * 80}\n').map((notice) {
      final split = notice.indexOf('\n\n');
      return LicenseEntryWithLineBreaks(
        notice.substring(0, split).split('\n'),
        notice.substring(split + 2),
      );
    }).toList();
    for (final name in [
      'Roboto',
      'Geist',
      'Geist Mono',
      'Inter',
      'Noto Sans',
      'Open Sans',
      'Poppins',
      'Atkinson Hyperlegible',
      'Lora',
      'com.android.tools.build:apksig:9.1.0',
      'androidx.core:core:1.18.0',
      'androidx.datastore:datastore-preferences-external-protobuf:1.1.7',
      'supabase_flutter',
    ]) {
      expect(
        entries.any((entry) => entry.packages.contains(name)),
        isTrue,
        reason: '$name must be in the compiled license bundle',
      );
    }
    // The test binding intentionally omits Flutter's built-in license loader.
    LicenseRegistry.addLicense(() => Stream.fromIterable(entries));
  });

  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(AndroidUpdatePlatform.channel, (call) async {
          expect(call.method, 'info');
          return {
            'version': '1.2.3',
            'buildNumber': '42',
            'directory': '/cache',
            'freeBytes': 1024,
          };
        });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(AndroidUpdatePlatform.channel, null);
  });

  for (final brightness in Brightness.values) {
    testWidgets('About and license detail work in $brightness at large text', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        MaterialApp(
          theme: janitraTheme(brightness: brightness),
          home: MediaQuery(
            data: const MediaQueryData(textScaler: TextScaler.linear(1.8)),
            child: const AboutPage(),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.runAsync(
        () => precacheImage(
          const AssetImage('assets/icons/janitra_launcher_1024.png'),
          tester.element(find.byType(AboutPage)),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(JanitraLogo), findsOneWidget);
      expect(find.text('Version 1.2.3 (Build 42)'), findsOneWidget);
      await expectLater(
        find.byType(AboutPage),
        matchesGoldenFile('goldens/about-${brightness.name}.png'),
      );
      await tester.ensureVisible(find.text('Third-party licenses'));
      await tester.tap(find.text('Third-party licenses'));
      await tester.pumpAndSettle();
      expect(find.byType(LicensePage), findsOneWidget);
      await tester.scrollUntilVisible(
        find.text('Roboto'),
        400,
        scrollable: find.byType(Scrollable).last,
      );
      await tester.tap(find.text('Roboto'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Apache License'), findsWidgets);
      await tester.pageBack();
      await tester.pumpAndSettle();
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(find.byType(AboutPage), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('missing native metadata keeps licenses accessible', (
    tester,
  ) async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(AndroidUpdatePlatform.channel, (_) async {
          throw PlatformException(code: 'unavailable');
        });
    await tester.pumpWidget(const MaterialApp(home: AboutPage()));
    await tester.pumpAndSettle();
    expect(find.text('Version information unavailable'), findsOneWidget);
    await tester.tap(find.text('Third-party licenses'));
    await tester.pumpAndSettle();
    expect(find.byType(LicensePage), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
