import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:janitra/features/workspace/home_setup_panel.dart';

void main() {
  testWidgets(
    'Theme-aware onboarding emphasizes progress and the next action',
    (tester) async {
      var addWorkplaceCalls = 0;
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(
            colorScheme: ColorScheme.fromSeed(
              seedColor: const Color(0xFF7850A0),
              brightness: Brightness.dark,
            ),
            useMaterial3: true,
          ),
          home: Scaffold(
            body: SingleChildScrollView(
              child: HomeSetupPanel(
                hasAgency: true,
                hasClient: true,
                hasWorkplace: false,
                canAddAgency: true,
                canManageAgency: true,
                isAdmin: false,
                onAddAgency: () {},
                onAddClient: () {},
                onAddWorkplace: () => addWorkplaceCalls++,
                onManageTeam: () {},
                onRefreshAccess: () {},
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final indicator = tester.widget<LinearProgressIndicator>(
        find.descendant(
          of: find.byKey(const ValueKey('home-setup-progress')),
          matching: find.byType(LinearProgressIndicator),
        ),
      );
      expect(indicator.value, closeTo(2 / 3, 0.001));
      expect(find.text('Create a workplace'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('home-setup-primary-action')));
      expect(addWorkplaceCalls, 1);
    },
  );
}
