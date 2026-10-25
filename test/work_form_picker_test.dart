import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:janitra/features/work/work_form.dart';

void main() {
  Future<Map<String, dynamic>?> launchForm(
    WidgetTester tester,
    List<WorkField> fields,
  ) async {
    Map<String, dynamic>? saved;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => FilledButton(
              onPressed: () => showModalBottomSheet<bool>(
                context: context,
                isScrollControlled: true,
                builder: (_) => WorkForm(
                  sheet: true,
                  title: 'Edit schedule',
                  fields: fields,
                  save: (values) async => saved = values,
                ),
              ),
              child: const Text('Open form'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open form'));
    await tester.pumpAndSettle();
    return saved;
  }

  testWidgets('activity and shift form labels sit above populated inputs', (
    tester,
  ) async {
    await launchForm(tester, const [
      WorkField(
        'site_id',
        'Workplace',
        value: 'site-1',
        choices: {'site-1': 'Main office'},
      ),
      WorkField('name', 'Schedule name', value: 'Morning shift'),
      WorkField(
        'starts_on',
        'Start date',
        value: '2026-10-18',
        input: WorkFieldInput.date,
      ),
    ]);
    expect(find.text('Workplace'), findsOneWidget);
    expect(find.text('Schedule name'), findsOneWidget);
    expect(find.text('Start date'), findsOneWidget);
    expect(find.text('Main office'), findsOneWidget);
    expect(find.text('Morning shift'), findsOneWidget);
    // No floating labels can collide with values or input outlines.
    for (final decorator in tester.widgetList<InputDecorator>(
      find.byType(InputDecorator),
    )) {
      expect(decorator.decoration.labelText, isNull);
    }
  });

  testWidgets('schedule date and time use interactive Material pickers', (
    tester,
  ) async {
    await launchForm(tester, const [
      WorkField(
        'starts_on',
        'Start date',
        value: '2026-10-18',
        input: WorkFieldInput.date,
      ),
      WorkField(
        'time',
        'Cleaning time',
        value: '08:00',
        input: WorkFieldInput.time,
      ),
    ]);
    await tester.tap(find.byType(TextFormField).at(0));
    await tester.pumpAndSettle();
    expect(find.byType(DatePickerDialog), findsOneWidget);
    await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(TextFormField).at(1));
    await tester.pumpAndSettle();
    expect(find.byType(TimePickerDialog), findsOneWidget);
    await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
    await tester.pumpAndSettle();
    expect(find.text('Edit schedule'), findsOneWidget);
  });

  testWidgets('shift ranges can be removed without typing time strings', (
    tester,
  ) async {
    Map<String, dynamic>? saved;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => FilledButton(
              onPressed: () => showModalBottomSheet<bool>(
                context: context,
                isScrollControlled: true,
                builder: (_) => WorkForm(
                  sheet: true,
                  title: 'Working hours',
                  fields: const [
                    WorkField(
                      'work',
                      'Working hours',
                      value: '07:00-12:00\n16:00-20:00',
                      input: WorkFieldInput.timeRanges,
                    ),
                  ],
                  save: (values) async => saved = values,
                ),
              ),
              child: const Text('Open form'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open form'));
    await tester.pumpAndSettle();
    expect(find.text('07:00  –  12:00'), findsOneWidget);
    expect(find.text('16:00  –  20:00'), findsOneWidget);
    await tester.tap(find.byTooltip('Remove time range').first);
    await tester.pumpAndSettle();
    expect(find.text('07:00  –  12:00'), findsNothing);
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(saved?['work'], '16:00-20:00');
  });

  testWidgets('time-range button opens a clock for editing', (tester) async {
    await launchForm(tester, const [
      WorkField(
        'work',
        'Working hours',
        value: '07:00-12:00',
        input: WorkFieldInput.timeRanges,
      ),
    ]);
    await tester.tap(find.text('07:00  –  12:00'));
    await tester.pumpAndSettle();
    expect(find.byType(TimePickerDialog), findsOneWidget);
    await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
    await tester.pumpAndSettle();
    expect(find.text('07:00  –  12:00'), findsOneWidget);
  });
}
