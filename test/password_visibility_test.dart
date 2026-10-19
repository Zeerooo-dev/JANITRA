import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:janitra/core/secret_text_form_field.dart';

void main() {
  testWidgets('each password visibility control works independently', (
    tester,
  ) async {
    final first = TextEditingController();
    final second = TextEditingController();
    addTearDown(() {
      first.dispose();
      second.dispose();
    });
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Form(
            child: Column(
              children: [
                SecretTextFormField(
                  controller: first,
                  decoration: const InputDecoration(labelText: 'Password'),
                ),
                SecretTextFormField(
                  controller: second,
                  decoration: const InputDecoration(
                    labelText: 'Confirm password',
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );

    expect(find.byTooltip('Show password'), findsNWidgets(2));
    final fields = find.byType(TextFormField);
    final inputs = find.byType(EditableText);
    expect(tester.widget<EditableText>(inputs.first).obscureText, isTrue);
    expect(tester.widget<EditableText>(inputs.last).obscureText, isTrue);

    await tester.enterText(fields.first, 'a-long-test-password');
    await tester.tap(find.byTooltip('Show password').first);
    await tester.pump();
    expect(tester.widget<EditableText>(inputs.first).obscureText, isFalse);
    expect(tester.widget<EditableText>(inputs.last).obscureText, isTrue);
    expect(first.text, 'a-long-test-password');

    await tester.tap(find.byTooltip('Hide password'));
    await tester.pump();
    expect(tester.widget<EditableText>(inputs.first).obscureText, isTrue);
    expect(first.text, 'a-long-test-password');
  });

  testWidgets(
    'revealed code hides again when the application is backgrounded',
    (tester) async {
      final code = TextEditingController();
      addTearDown(code.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SecretTextFormField(
              controller: code,
              visibilityLabel: 'code',
              decoration: const InputDecoration(labelText: 'Code'),
            ),
          ),
        ),
      );
      await tester.enterText(find.byType(TextFormField), '123456');
      await tester.tap(find.byTooltip('Show code'));
      await tester.pump();
      expect(
        tester.widget<EditableText>(find.byType(EditableText)).obscureText,
        isFalse,
      );
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      await tester.pump();
      expect(
        tester.widget<EditableText>(find.byType(EditableText)).obscureText,
        isTrue,
      );
      expect(code.text, '123456');
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();
    },
  );

  testWidgets('disabled and replaced password fields reset visibility', (
    tester,
  ) async {
    final first = TextEditingController(text: 'first-test-password');
    final second = TextEditingController(text: 'second-test-password');
    addTearDown(first.dispose);
    addTearDown(second.dispose);
    Future<void> show(
      TextEditingController controller, {
      bool enabled = true,
    }) => tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SecretTextFormField(controller: controller, enabled: enabled),
        ),
      ),
    );

    await show(first);
    await tester.tap(find.byTooltip('Show password'));
    await tester.pump();
    expect(
      tester.widget<EditableText>(find.byType(EditableText)).obscureText,
      isFalse,
    );

    await show(first, enabled: false);
    expect(
      tester.widget<EditableText>(find.byType(EditableText)).obscureText,
      isTrue,
    );
    expect(
      tester.widget<IconButton>(find.byType(IconButton)).onPressed,
      isNull,
    );
    await show(first);
    await tester.tap(find.byTooltip('Show password'));
    await tester.pump();
    expect(
      tester.widget<EditableText>(find.byType(EditableText)).obscureText,
      isFalse,
    );

    await show(second);
    expect(
      tester.widget<EditableText>(find.byType(EditableText)).obscureText,
      isTrue,
    );
    expect(first.text, 'first-test-password');
    expect(second.text, 'second-test-password');
    expect(tester.takeException(), isNull);
  });
}
