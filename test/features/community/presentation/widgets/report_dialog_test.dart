import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:vilvia/features/community/presentation/widgets/report_dialog.dart';

void main() {
  Widget launcher(Future<void> Function(String) onSubmit) => MaterialApp(
    home: Builder(
      builder: (context) => Scaffold(
        body: TextButton(
          onPressed: () =>
              showReportDialog(context: context, onSubmit: onSubmit),
          child: const Text('Open'),
        ),
      ),
    ),
  );

  testWidgets('empty and whitespace-only reasons cannot submit', (
    tester,
  ) async {
    var calls = 0;
    await tester.pumpWidget(launcher((_) async => calls++));
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();

    FilledButton submit() =>
        tester.widget(find.widgetWithText(FilledButton, 'Submit'));
    expect(submit().onPressed, isNull);
    await tester.enterText(find.widgetWithText(TextField, 'Reason'), '   ');
    await tester.pump();
    expect(submit().onPressed, isNull);
    expect(calls, 0);
  });

  testWidgets('reason input enforces the 500 character limit', (tester) async {
    await tester.pumpWidget(launcher((_) async {}));
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();

    await tester.enterText(find.widgetWithText(TextField, 'Reason'), 'x' * 501);
    await tester.pump();

    final field = tester.widget<TextField>(
      find.widgetWithText(TextField, 'Reason'),
    );
    expect(field.controller!.text, hasLength(500));
  });

  testWidgets('pending submission blocks duplicate requests', (tester) async {
    final pending = Completer<void>();
    var calls = 0;
    await tester.pumpWidget(
      launcher((_) {
        calls++;
        return pending.future;
      }),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextField, 'Reason'), 'Reason');
    await tester.pump();

    await tester.tap(find.text('Submit'));
    await tester.pump();
    expect(calls, 1);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(
      tester
          .widget<TextButton>(find.widgetWithText(TextButton, 'Cancel'))
          .onPressed,
      isNull,
    );

    pending.complete();
    await tester.pumpAndSettle();
    expect(find.text('Report content'), findsNothing);
  });

  testWidgets('failure preserves reason and allows retry', (tester) async {
    var calls = 0;
    await tester.pumpWidget(
      launcher((_) async {
        calls++;
        throw Exception('network');
      }),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextField, 'Reason'),
      'Keep this reason',
    );
    await tester.pump();
    await tester.tap(find.text('Submit'));
    await tester.pumpAndSettle();

    expect(calls, 1);
    expect(find.text('Keep this reason'), findsOneWidget);
    expect(
      find.text('Could not submit report. Please try again.'),
      findsOneWidget,
    );
    expect(
      tester
          .widget<FilledButton>(find.widgetWithText(FilledButton, 'Submit'))
          .onPressed,
      isNotNull,
    );
  });
}
