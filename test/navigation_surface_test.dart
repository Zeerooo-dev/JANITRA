import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:janitra/core/appearance_settings.dart';
import 'package:janitra/core/app_theme.dart';
import 'package:janitra/core/aurora_glass.dart';

void main() {
  for (final brightness in Brightness.values) {
    for (final contrast in [false, true]) {
      testWidgets(
        'Navigation glass remains readable and interactive in $brightness, high contrast $contrast',
        (tester) async {
          tester.view.physicalSize = const Size(320, 640);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          final settings = AppearanceSettings()..highContrast = contrast;
          final theme = janitraTheme(
            brightness: brightness,
            highContrast: contrast,
          );
          var selected = 0;
          await tester.pumpWidget(
            AppearanceScope(
              settings: settings,
              child: MaterialApp(
                theme: theme,
                home: StatefulBuilder(
                  builder: (context, setState) {
                    return JanitraAuroraBackground(
                      child: Scaffold(
                        backgroundColor: Colors.transparent,
                        appBar: AppBar(
                          backgroundColor: Colors.transparent,
                          flexibleSpace: const JanitraNavigationSurface(
                            child: SizedBox.expand(),
                          ),
                          title: const Text('Workspace'),
                        ),
                        body: const Center(
                          key: ValueKey('navigation-test-content'),
                          child: Text('Work content'),
                        ),
                        bottomNavigationBar: SafeArea(
                          top: false,
                          minimum: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                          child: JanitraNavigationSurface(
                            radius: 26,
                            child: NavigationBar(
                              backgroundColor: Colors.transparent,
                              selectedIndex: selected,
                              onDestinationSelected: (value) =>
                                  setState(() => selected = value),
                              destinations: const [
                                NavigationDestination(
                                  icon: Icon(Icons.home),
                                  label: 'Home',
                                ),
                                NavigationDestination(
                                  icon: Icon(Icons.checklist),
                                  label: 'Tasks',
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
          );
          final surfaces = find.byType(JanitraNavigationSurface);
          expect(surfaces, findsNWidgets(2));
          final bottom = tester.getRect(surfaces.last);
          expect(bottom.left, 16);
          expect(bottom.right, 304);
          expect(bottom.bottom, lessThanOrEqualTo(628));
          expect(
            tester
                .getRect(find.byKey(const ValueKey('navigation-test-content')))
                .bottom,
            lessThanOrEqualTo(bottom.top),
          );
          expect(
            tester.widget<JanitraNavigationSurface>(surfaces.last).radius,
            26,
          );
          for (var i = 0; i < 2; i++) {
            final surface = surfaces.at(i);
            expect(
              find.descendant(of: surface, matching: find.byType(ClipRRect)),
              findsWidgets,
            );
            expect(
              find.descendant(
                of: surface,
                matching: find.byType(BackdropFilter),
              ),
              contrast ? findsNothing : findsOneWidget,
            );
            final decoration =
                tester
                        .widget<DecoratedBox>(
                          find
                              .descendant(
                                of: surface,
                                matching: find.byType(DecoratedBox),
                              )
                              .first,
                        )
                        .decoration
                    as BoxDecoration;
            for (final backdrop in [Colors.black, Colors.white]) {
              expect(
                colorContrast(
                  theme.appBarTheme.foregroundColor!,
                  Color.alphaBlend(decoration.color!, backdrop),
                ),
                greaterThanOrEqualTo(contrast ? 7 : 4.5),
              );
            }
          }
          await tester.tap(find.text('Tasks'));
          await tester.pumpAndSettle();
          expect(
            tester
                .widget<NavigationBar>(find.byType(NavigationBar))
                .selectedIndex,
            1,
          );
          expect(find.text('Work content'), findsOneWidget);
          expect(tester.takeException(), isNull);
          await tester.pumpWidget(const SizedBox());
          settings.dispose();
        },
      );
    }
  }

  testWidgets('Custom mid-tone background falls back to a solid readable bar', (
    tester,
  ) async {
    final theme = janitraTheme(background: const Color(0xFF777777));
    await tester.pumpWidget(
      MaterialApp(
        theme: theme,
        home: const Scaffold(
          body: JanitraNavigationSurface(child: Text('Readable controls')),
        ),
      ),
    );
    expect(find.byType(BackdropFilter), findsNothing);
    final decoration =
        tester.widget<DecoratedBox>(find.byType(DecoratedBox).first).decoration
            as BoxDecoration;
    expect(decoration.color, theme.appBarTheme.backgroundColor);
    expect(
      colorContrast(theme.appBarTheme.foregroundColor!, decoration.color!),
      greaterThanOrEqualTo(4.5),
    );
  });
}
