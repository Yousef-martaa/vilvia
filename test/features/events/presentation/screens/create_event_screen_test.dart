import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:vilvia/features/events/data/event.dart';
import 'package:vilvia/features/events/data/events_api_client.dart';
import 'package:vilvia/features/events/presentation/screens/create_event_screen.dart';

Event _fakeEvent() => Event(
      id: '1',
      title: 'Created Event',
      description: 'A short description',
      location: 'Community Centre',
      startsAt: DateTime.utc(2026, 8, 22, 10),
      endsAt: DateTime.utc(2026, 8, 22, 12),
      createdAt: DateTime(2024),
      updatedAt: DateTime(2024),
    );

class _SpyApiClient extends EventsApiClient {
  _SpyApiClient({this.createEventError}) : super(baseUrl: 'http://test');

  final Object? createEventError;

  bool createEventCalled = false;
  String? capturedTitle;
  String? capturedDescription;
  String? capturedLocation;
  DateTime? capturedStartsAt;
  DateTime? capturedEndsAt;

  @override
  Future<Event> createEvent({
    required String title,
    required String description,
    required String location,
    required DateTime startsAt,
    DateTime? endsAt,
  }) async {
    createEventCalled = true;
    capturedTitle = title;
    capturedDescription = description;
    capturedLocation = location;
    capturedStartsAt = startsAt;
    capturedEndsAt = endsAt;
    if (createEventError != null) throw createEventError!;
    return _fakeEvent();
  }
}

void main() {
  Widget wrap(EventsApiClient client) =>
      MaterialApp(home: CreateEventScreen(apiClient: client));

  Future<void> fillRequiredTextFields(WidgetTester tester) async {
    await tester.enterText(
      find.widgetWithText(TextField, 'Title'),
      'Parent & Baby Playgroup',
    );
    await tester.enterText(
      find.widgetWithText(TextField, 'Location'),
      'Community Centre',
    );
    await tester.enterText(
      find.widgetWithText(TextField, 'Description'),
      'A relaxed drop-in playgroup.',
    );
  }

  /// Drives the built-in Material date/time pickers, accepting whatever
  /// their default initial value is (today / now) -- sufficient for
  /// these tests, which only need *a* valid, non-null starts_at.
  Future<void> pickStartsAt(WidgetTester tester) async {
    await tester.tap(find.text('Choose start date & time'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
  }

  testWidgets('valid form submits and calls createEvent with the entered '
      'values', (tester) async {
    final client = _SpyApiClient();

    await tester.pumpWidget(wrap(client));
    await fillRequiredTextFields(tester);
    await pickStartsAt(tester);

    await tester.tap(find.text('Create Draft Event'));
    await tester.pumpAndSettle();

    expect(client.createEventCalled, isTrue);
    expect(client.capturedTitle, 'Parent & Baby Playgroup');
    expect(client.capturedLocation, 'Community Centre');
    expect(client.capturedDescription, 'A relaxed drop-in playgroup.');
    expect(client.capturedStartsAt, isNotNull);
    expect(client.capturedEndsAt, isNull);
  });

  testWidgets('an empty title does not submit and shows a validation error',
      (tester) async {
    final client = _SpyApiClient();

    await tester.pumpWidget(wrap(client));
    await tester.enterText(find.widgetWithText(TextField, 'Location'), 'Loc');
    await tester.enterText(
      find.widgetWithText(TextField, 'Description'),
      'Desc',
    );
    await pickStartsAt(tester);

    await tester.tap(find.text('Create Draft Event'));
    await tester.pumpAndSettle();

    expect(client.createEventCalled, isFalse);
    expect(find.textContaining('Please enter a title'), findsOneWidget);
  });

  testWidgets(
      'submitting without choosing a start date/time does not submit',
      (tester) async {
    final client = _SpyApiClient();

    await tester.pumpWidget(wrap(client));
    await fillRequiredTextFields(tester);

    await tester.tap(find.text('Create Draft Event'));
    await tester.pumpAndSettle();

    expect(client.createEventCalled, isFalse);
    expect(
      find.textContaining('Please choose a start date and time'),
      findsOneWidget,
    );
  });

  testWidgets(
      'successful creation shows a message explicit that the Event is a '
      'draft, not publicly visible yet', (tester) async {
    final client = _SpyApiClient();

    await tester.pumpWidget(wrap(client));
    await fillRequiredTextFields(tester);
    await pickStartsAt(tester);

    await tester.tap(find.text('Create Draft Event'));
    await tester.pumpAndSettle();

    expect(find.text('Event created as a draft'), findsOneWidget);
    expect(
      find.textContaining('will not appear in the public Events list'),
      findsOneWidget,
    );
  });

  testWidgets('a failed creation shows an error and stays on the form',
      (tester) async {
    final client = _SpyApiClient(createEventError: Exception('403'));

    await tester.pumpWidget(wrap(client));
    await fillRequiredTextFields(tester);
    await pickStartsAt(tester);

    await tester.tap(find.text('Create Draft Event'));
    await tester.pumpAndSettle();

    expect(find.text('Event created as a draft'), findsNothing);
    expect(find.textContaining('403'), findsOneWidget);
  });
}
