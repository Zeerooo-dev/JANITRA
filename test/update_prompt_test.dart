import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:janitra/core/app_theme.dart';
import 'package:janitra/features/updates/apk_updater.dart';
import 'package:janitra/features/updates/update_prompt.dart';

import 'support/update_fixtures.dart';

class DialogUpdater extends ApkUpdater {
  DialogUpdater(UpdatePlatform platform)
    : super(
        platform: platform,
        repository: updateRepository,
        client: MockClient((_) async => http.Response('[]', 200)),
      );
  late Completer<String> done = Completer<String>();
  Future<AppRelease?>? checkResult;
  int checks = 0;
  int remembered = 0;
  int cleared = 0;
  (AppRelease, String)? saved;
  @override
  Future<(AppRelease, String)?> restorePendingPermission() async => saved;
  @override
  Future<void> rememberPermission(String path, AppRelease release) async {
    remembered++;
    saved = (release, path);
  }

  @override
  Future<void> clearPendingPermission() async {
    cleared++;
    saved = null;
  }

  @override
  Future<AppRelease?> check() {
    checks++;
    return checkResult ?? Future.value(testRelease);
  }

  void Function(int, int)? progress;
  @override
  Future<String> download(
    AppRelease release,
    void Function(int, int) progress, {
    void Function()? verifying,
  }) {
    this.progress = progress;
    return done.future;
  }
}

void main() {
  void background(WidgetTester tester) {
    for (final state in [
      AppLifecycleState.inactive,
      AppLifecycleState.hidden,
      AppLifecycleState.paused,
    ]) {
      tester.binding.handleAppLifecycleStateChanged(state);
    }
  }

  void foreground(WidgetTester tester) {
    for (final state in [
      AppLifecycleState.hidden,
      AppLifecycleState.inactive,
      AppLifecycleState.resumed,
    ]) {
      tester.binding.handleAppLifecycleStateChanged(state);
    }
  }

  late FakeUpdatePlatform platform;
  late DialogUpdater updater;
  setUp(() {
    platform = FakeUpdatePlatform('/unused');
    updater = DialogUpdater(platform);
  });
  tearDown(() {
    updater.dispose();
  });

  Future<void> show(
    WidgetTester tester, {
    ThemeData? theme,
    String? initialPath,
  }) async {
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpWidget(
      MaterialApp(
        theme: theme ?? janitraTheme(),
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => showDialog<void>(
                context: context,
                builder: (_) => UpdateDialog(
                  updater: updater,
                  release: testRelease,
                  initialPath: initialPath,
                ),
              ),
              child: const Text('Show update'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Show update'));
    await tester.pumpAndSettle();
  }

  testWidgets('shows branding, version, notes, Update Now and Later', (
    tester,
  ) async {
    await show(tester);
    expect(find.byType(JanitraLogo), findsOneWidget);
    expect(find.text('JANITRA 1.1.0'), findsOneWidget);
    expect(find.text(testRelease.notes), findsOneWidget);
    expect(find.text('Update Now'), findsOneWidget);
    await tester.tap(find.text('Later'));
    await tester.pumpAndSettle();
    expect(find.byType(UpdateDialog), findsNothing);
    expect(platform.installed, 0);
  });

  testWidgets(
    'restored download needs a fresh install action after process restart',
    (tester) async {
      await show(tester, initialPath: '/verified.apk');
      expect(find.text('Update ready'), findsOneWidget);
      expect(find.text('Install update'), findsOneWidget);
      background(tester);
      foreground(tester);
      await tester.pumpAndSettle();
      expect(platform.installed, 0);
      expect(updater.progress, isNull);
      await tester.tap(find.text('Install update'));
      await tester.pumpAndSettle();
      expect(platform.installed, 1);
      expect(updater.cleared, greaterThan(0));
    },
  );

  testWidgets('real progress and verification gate installer', (tester) async {
    await show(tester);
    await tester.tap(find.text('Update Now'));
    await tester.pump();
    updater.progress!(2, 4);
    await tester.pump();
    expect(
      tester
          .widget<LinearProgressIndicator>(find.byType(LinearProgressIndicator))
          .value,
      0.5,
    );
    expect(platform.installed, 0);
    updater.done.complete('/verified.apk');
    await tester.pumpAndSettle();
    expect(platform.installed, 1);
    expect(find.byType(UpdateDialog), findsNothing);
  });

  testWidgets('download failure is local and offers retry or Later', (
    tester,
  ) async {
    await show(tester);
    await tester.tap(find.text('Update Now'));
    await tester.pump();
    updater.done.completeError(
      const UpdateFailure('Not enough storage. Free some space and try again.'),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('Not enough storage'), findsOneWidget);
    expect(find.text('Try again'), findsOneWidget);
    expect(platform.installed, 0);
    await tester.tap(find.text('Later'));
    await tester.pumpAndSettle();
    expect(find.text('Show update'), findsOneWidget);
  });

  testWidgets('permission settings return retries verified installation', (
    tester,
  ) async {
    platform.allowed = false;
    await show(tester);
    await tester.tap(find.text('Update Now'));
    await tester.pump();
    updater.done.complete('/verified.apk');
    await tester.pumpAndSettle();
    expect(platform.installed, 0);
    await tester.tap(find.text('Allow installation'));
    await tester.pumpAndSettle();
    expect(platform.settings, 1);
    background(tester);
    platform.allowed = true;
    foreground(tester);
    await tester.pumpAndSettle();
    expect(platform.installed, 1);
  });

  testWidgets(
    'permission denial keeps Later available without repeated settings prompts',
    (tester) async {
      platform.allowed = false;
      await show(tester);
      await tester.tap(find.text('Update Now'));
      await tester.pump();
      updater.done.complete('/verified.apk');
      await tester.pumpAndSettle();
      await tester.tap(find.text('Allow installation'));
      await tester.pumpAndSettle();
      background(tester);
      foreground(tester);
      await tester.pumpAndSettle();
      expect(platform.settings, 1);
      expect(platform.installed, 0);
      await tester.tap(find.text('Later'));
      await tester.pumpAndSettle();
    },
  );

  testWidgets('finishing download in background waits for foreground', (
    tester,
  ) async {
    await show(tester);
    await tester.tap(find.text('Update Now'));
    await tester.pump();
    background(tester);
    updater.done.complete('/verified.apk');
    await tester.pump();
    expect(platform.installed, 0);
    foreground(tester);
    await tester.pumpAndSettle();
    expect(platform.installed, 1);
  });

  testWidgets(
    'Later cancels an in-flight permission action without opening settings or installing',
    (tester) async {
      platform.allowed = false;
      await show(tester);
      await tester.tap(find.text('Update Now'));
      await tester.pump();
      updater.done.complete('/verified.apk');
      await tester.pumpAndSettle();
      platform.allowedFuture = Completer<bool>();
      await tester.tap(find.text('Allow installation'));
      await tester.pump();
      await tester.tap(find.text('Later'));
      await tester.pumpAndSettle();
      platform.allowedFuture!.complete(true);
      await tester.pumpAndSettle();
      expect(platform.installed, 0);
      expect(platform.settings, 0);
      expect(find.byType(UpdateDialog), findsNothing);
    },
  );

  testWidgets(
    'installer failure after permission grant keeps a working install retry',
    (tester) async {
      platform.allowed = false;
      await show(tester);
      await tester.tap(find.text('Update Now'));
      await tester.pump();
      updater.done.complete('/verified.apk');
      await tester.pumpAndSettle();
      await tester.tap(find.text('Allow installation'));
      await tester.pumpAndSettle();
      background(tester);
      platform.allowed = true;
      platform.installError = PlatformException(code: 'installer');
      foreground(tester);
      await tester.pumpAndSettle();
      expect(find.text('Install update'), findsOneWidget);
      platform.installError = null;
      await tester.tap(find.text('Install update'));
      await tester.pumpAndSettle();
      expect(platform.installed, 1);
      expect(platform.settings, 1);
    },
  );

  testWidgets(
    'failed download retries successfully without leaving the workspace',
    (tester) async {
      await show(tester);
      await tester.tap(find.text('Update Now'));
      await tester.pump();
      updater.done.completeError(const UpdateFailure('Connection lost.'));
      await tester.pumpAndSettle();
      updater.done = Completer<String>();
      await tester.tap(find.text('Try again'));
      await tester.pump();
      updater.done.complete('/verified.apk');
      await tester.pumpAndSettle();
      expect(platform.installed, 1);
      expect(find.text('Show update'), findsOneWidget);
    },
  );

  testWidgets(
    'startup check is nonblocking; Later preserves selected tab and route state',
    (tester) async {
      final response = Completer<AppRelease?>();
      final service = DialogUpdater(platform)..checkResult = response.future;
      final navigator = GlobalKey<NavigatorState>();
      final workspace = GlobalKey();
      var tab = 0;
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpWidget(
        MaterialApp(
          navigatorKey: navigator,
          builder: (_, child) => UpdatePromptHost(
            navigatorKey: navigator,
            updater: service,
            child: child!,
          ),
          home: StatefulBuilder(
            key: workspace,
            builder: (_, setState) => Scaffold(
              body: Column(
                children: [
                  Text('Tab $tab'),
                  TextButton(
                    onPressed: () => setState(() => tab = 2),
                    child: const Text('Team'),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
      final state = workspace.currentState;
      await tester.tap(find.text('Team'));
      await tester.pump(const Duration(seconds: 3));
      expect(find.text('Tab 2'), findsOneWidget);
      expect(find.byType(UpdateDialog), findsNothing);
      response.complete(testRelease);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Later'));
      await tester.pumpAndSettle();
      expect(identical(state, workspace.currentState), isTrue);
      expect(find.text('Tab 2'), findsOneWidget);
      for (var i = 0; i < 4; i++) {
        background(tester);
        foreground(tester);
      }
      await tester.pump(const Duration(seconds: 3));
      expect(service.checks, 1);
      expect(find.byType(UpdateDialog), findsNothing);
      await tester.pumpWidget(const SizedBox());
      service.dispose();
    },
  );

  for (final brightness in [Brightness.light, Brightness.dark]) {
    testWidgets('popup fits at large text on small ${brightness.name} screen', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1;
      tester.platformDispatcher.textScaleFactorTestValue = 2;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
        tester.platformDispatcher.clearTextScaleFactorTestValue();
      });
      await show(tester, theme: janitraTheme(brightness: brightness));
      expect(tester.takeException(), isNull);
      await tester.ensureVisible(find.text('Later'));
      await tester.tap(find.text('Later'));
      await tester.pumpAndSettle();
      expect(find.byType(UpdateDialog), findsNothing);
    });
  }
}
