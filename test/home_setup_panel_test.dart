import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:janitra/features/workspace/home_setup_panel.dart';

void main() {
  Future<void> showPanel(
    WidgetTester tester, {
    bool hasAgency = false,
    bool hasClient = false,
    bool hasWorkplace = false,
    bool canAddAgency = true,
    bool canManageAgency = true,
    bool isAdmin = false,
    VoidCallback? addAgency,
    VoidCallback? addClient,
    VoidCallback? addWorkplace,
    VoidCallback? manageTeam,
    VoidCallback? refresh,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: HomeSetupPanel(
                hasAgency: hasAgency,
                hasClient: hasClient,
                hasWorkplace: hasWorkplace,
                canAddAgency: canAddAgency,
                canManageAgency: canManageAgency,
                isAdmin: isAdmin,
                onAddAgency: addAgency ?? () {},
                onAddClient: addClient ?? () {},
                onAddWorkplace: addWorkplace ?? () {},
                onManageTeam: manageTeam ?? () {},
                onRefreshAccess: refresh ?? () {},
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('New authorized Supervisor gets an agency action', (
    tester,
  ) async {
    var agencyCalls = 0;
    await showPanel(tester, addAgency: () => agencyCalls++);
    expect(find.text('Set up your workspace'), findsOneWidget);
    expect(find.text('Add Manpower Agency'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('home-setup-primary-action')));
    expect(agencyCalls, 1);
    expect(find.text('Complete earlier steps first'), findsWidgets);
  });

  testWidgets('Next step depends on existing data', (tester) async {
    var clientCalls = 0;
    await showPanel(tester, hasAgency: true, addClient: () => clientCalls++);
    expect(find.text('Add your first client'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('home-setup-primary-action')));
    expect(clientCalls, 1);

    var siteCalls = 0;
    await showPanel(
      tester,
      hasAgency: true,
      hasClient: true,
      addWorkplace: () => siteCalls++,
    );
    expect(find.text('Create a workplace'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('home-setup-primary-action')));
    expect(siteCalls, 1);
  });

  testWidgets('Site-specific access never exposes an agency creation action', (
    tester,
  ) async {
    var addCalls = 0;
    var refreshCalls = 0;
    await showPanel(
      tester,
      canAddAgency: false,
      canManageAgency: false,
      addAgency: () => addCalls++,
      refresh: () => refreshCalls++,
    );
    expect(find.text('Workspace access needed'), findsOneWidget);
    expect(find.text('Add Manpower Agency'), findsNothing);
    await tester.tap(find.byKey(const ValueKey('home-setup-primary-action')));
    expect(addCalls, 0);
    expect(refreshCalls, 1);
  });

  testWidgets('Admin can open unassigned Team without an agency', (
    tester,
  ) async {
    var teamCalls = 0;
    await showPanel(tester, isAdmin: true, manageTeam: () => teamCalls++);
    await tester.tap(find.text('Manage unassigned people'));
    expect(teamCalls, 1);
  });

  testWidgets('Team quick action uses existing navigation', (tester) async {
    var teamCalls = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: HomeTeamQuickAction(onManageTeam: () => teamCalls++),
        ),
      ),
    );
    await tester.tap(find.text('Manage your team'));
    expect(teamCalls, 1);
  });

  testWidgets('Setup fits a narrow phone with large text', (tester) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await showPanel(tester, hasAgency: true);
    await tester.ensureVisible(find.byKey(const ValueKey('home-setup-step-3')));
    await tester.pumpAndSettle();
  });
}
