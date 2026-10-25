import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:janitra/features/work/personal_schedule_page.dart';

void main() {
  final shift = <String, dynamic>{
    'name': 'Morning and evening',
    'is_active': true,
    'starts_on': '2026-10-18',
    'ends_on': null,
    'weekdays': [1, 2, 3, 4, 5, 6],
  };
  final segments = <Map<String, dynamic>>[
    {'kind': 'work', 'start_minute': 420, 'end_minute': 720},
    {'kind': 'break', 'start_minute': 720, 'end_minute': 780},
    {'kind': 'work', 'start_minute': 960, 'end_minute': 1200},
  ];

  testWidgets('employee shift shows weekdays, dates, work and breaks', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: ScheduleShiftCard(shift: shift, segments: segments),
          ),
        ),
      ),
    );
    expect(find.text('Morning and evening'), findsOneWidget);
    expect(find.text('Active'), findsOneWidget);
    expect(find.text('Mon'), findsOneWidget);
    expect(find.text('Sun'), findsOneWidget);
    expect(find.text('07:00 – 12:00'), findsOneWidget);
    expect(find.text('Break'), findsOneWidget);
    expect(find.text('16:00 – 20:00'), findsOneWidget);
  });

  testWidgets('paused overnight shift remains readable on narrow phones', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 720);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: ScheduleShiftCard(
              shift: {
                ...shift,
                'is_active': false,
                'weekdays': [7],
              },
              segments: const [
                {'kind': 'work', 'start_minute': 1380, 'end_minute': 1500},
              ],
            ),
          ),
        ),
      ),
    );
    expect(find.text('Paused'), findsOneWidget);
    expect(find.text('23:00 – 01:00 +1 day'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
