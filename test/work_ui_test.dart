import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/testing.dart';
import 'package:janitra/features/work/task_page.dart';
import 'package:janitra/features/work/task_record.dart';
import 'package:janitra/features/work/work_repository.dart';
import 'package:janitra/features/workspace/workspace_access.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'fixtures/workspace_backend.dart';
import 'workflows_test.dart' show sampleTask;

void main() {
  Future<void> settleFunctions(WidgetTester tester) async {
    for (var i = 0; i < 4; i++) {
      await tester.pump();
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 40)),
      );
    }
    await tester.pumpAndSettle();
  }

  testWidgets(
    'Supervisor PIN verification leaves work pending until separate final approval',
    (tester) async {
      final backend = WorkspaceTestBackend();
      final task = sampleTask(status: 'PENDING_APPROVAL');
      task.data['submitted_at'] = '2026-10-12T01:00:00Z';
      backend.workTables['task_work_view'] = [task.data];
      final client = (await tester.runAsync(
        () => Future.value(
          SupabaseClient(
            'https://example.supabase.co',
            'test',
            httpClient: MockClient(backend.handle),
            authOptions: const AuthClientOptions(autoRefreshToken: false),
          ),
        ),
      ))!;
      await tester.runAsync(
        () => client.auth.signInWithPassword(
          email: 'test@example.test',
          password: 'test-only',
        ),
      );
      addTearDown(() async {
        await tester.pumpWidget(const SizedBox());
        await tester.runAsync(client.dispose);
      });
      await tester.pumpWidget(
        MaterialApp(
          home: TaskDetailsPage(
            repo: WorkRepository(client),
            task: task,
            access: WorkspaceAccess(
              fullName: backend.fullName,
              roles: backend.roles,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Submission & review'), findsOneWidget);
      expect(find.text('Official submission'), findsOneWidget);
      expect(find.text('Review deadline'), findsOneWidget);
      final confirm = find.widgetWithText(FilledButton, 'Confirm Work');
      await tester.ensureVisible(confirm);
      await tester.tap(confirm);
      await tester.pumpAndSettle();
      expect(find.text('Supervisor PIN'), findsOneWidget);
      expect(find.byType(TextFormField), findsNothing);
      final confirmPin = find.widgetWithText(
        FilledButton,
        'Verify & confirm work',
      );
      expect(tester.widget<FilledButton>(confirmPin).onPressed, isNull);
      for (final digit in ['0', '0', '4', '2']) {
        final digitButton = find.widgetWithText(OutlinedButton, digit);
        await tester.ensureVisible(digitButton);
        await tester.tap(digitButton);
        await tester.pump();
      }
      expect(tester.widget<FilledButton>(confirmPin).onPressed, isNotNull);
      await tester.ensureVisible(confirmPin);
      await tester.tap(confirmPin);
      await settleFunctions(tester);
      expect(find.text('Pending Approval'), findsOneWidget);
      expect(find.textContaining('Confirmed by'), findsOneWidget);
      expect(
        backend.functionCalls.where((c) => c['action'] == 'approve'),
        isEmpty,
      );
      await tester.ensureVisible(find.text('Final Work Approval'));
      await tester.tap(find.text('Final Work Approval'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Approve Work'));
      await settleFunctions(tester);
      expect(find.text('Approved'), findsOneWidget);
      expect(backend.functionCalls.map((c) => c['action']), [
        'verify',
        'approve',
      ]);
      expect(backend.functionCalls.last, isNot(contains('pin')));
    },
  );
  testWidgets('Supervisor PIN clears on background and supports correction', (
    tester,
  ) async {
    final backend = WorkspaceTestBackend();
    final client = (await tester.runAsync(
      () => Future.value(
        SupabaseClient(
          'https://example.supabase.co',
          'test',
          httpClient: MockClient(backend.handle),
          authOptions: const AuthClientOptions(autoRefreshToken: false),
        ),
      ),
    ))!;
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox());
      await tester.runAsync(client.dispose);
    });
    tester.view.physicalSize = const Size(320, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    var submitted = false;
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: const TextScaler.linear(2)),
          child: child!,
        ),
        home: Scaffold(
          body: Builder(
            builder: (context) => Center(
              child: FilledButton(
                onPressed: () => showModalBottomSheet<TaskRecord>(
                  context: context,
                  isScrollControlled: true,
                  builder: (_) => SupervisorConfirmPinSheet(
                    client: client,
                    taskName: 'Test cleaning',
                    onConfirm: (pin) async {
                      submitted = true;
                      expect(pin, '0042');
                      return sampleTask(status: 'PENDING_APPROVAL');
                    },
                  ),
                ),
                child: const Text('Open PIN'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open PIN'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.widgetWithText(OutlinedButton, '4'));
    await tester.tap(find.widgetWithText(OutlinedButton, '4'));
    await tester.pump();
    expect(find.bySemanticsLabel('1 of 4 PIN digits entered'), findsOneWidget);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    await tester.pump();
    expect(find.bySemanticsLabel('0 of 4 PIN digits entered'), findsOneWidget);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    for (final digit in ['0', '0', '4', '3']) {
      final digitButton = find.widgetWithText(OutlinedButton, digit);
      await tester.ensureVisible(digitButton);
      await tester.tap(digitButton);
      await tester.pump();
    }
    await tester.ensureVisible(find.byIcon(Icons.backspace_outlined));
    await tester.tap(find.byIcon(Icons.backspace_outlined));
    await tester.pump();
    await tester.ensureVisible(find.widgetWithText(OutlinedButton, '2'));
    await tester.tap(find.widgetWithText(OutlinedButton, '2'));
    await tester.pump();
    await tester.ensureVisible(find.text('Verify & confirm work'));
    await tester.tap(find.text('Verify & confirm work'));
    await tester.pumpAndSettle();
    expect(submitted, isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'PIN keypad handles narrow screen at large text and clears on background',
    (tester) async {
      final client = (await tester.runAsync(
        () => Future.value(
          SupabaseClient(
            'https://example.supabase.co',
            'test',
            httpClient: MockClient(WorkspaceTestBackend().handle),
            authOptions: const AuthClientOptions(autoRefreshToken: false),
          ),
        ),
      ))!;
      await tester.runAsync(
        () => client.auth.signInWithPassword(
          email: 'test@example.test',
          password: 'test-only',
        ),
      );
      addTearDown(() async {
        await tester.pumpWidget(const SizedBox());
        await tester.runAsync(client.dispose);
      });
      tester.view.physicalSize = const Size(320, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        MaterialApp(
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: const TextScaler.linear(2)),
            child: child!,
          ),
          home: EmployeePinPage(
            repo: WorkRepository(client),
            draft: WorkDraft(
              task: sampleTask(),
              remarks: '',
              claimedAt: '2026-10-12T01:00:00Z',
              requestId: 'test',
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.ensureVisible(find.text('0'));
      await tester.tap(find.text('0'));
      await tester.pump();
      expect(find.text('●'), findsOneWidget);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      await tester.pump();
      expect(find.text('●'), findsNothing);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();
    },
  );
}
