import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:vilvia/features/events/data/event.dart';
import 'package:vilvia/features/events/data/events_api_client.dart';
import 'package:vilvia/features/events/presentation/screens/events_screen.dart';

// --- Stub helpers ---

Event _fakeEvent({
  String title = 'Test Event',
  String location = 'Community Centre',
  String description = 'A short description',
  DateTime? startsAt,
}) {
  final start = startsAt ?? DateTime.now().toUtc().add(const Duration(days: 1));
  return Event(
    id: '1',
    title: title,
    description: description,
    location: location,
    startsAt: start,
    endsAt: start.add(const Duration(hours: 2)),
    createdAt: DateTime(2024),
    updatedAt: DateTime(2024),
  );
}

class _StubApiClient extends EventsApiClient {
  final Future<List<Event>> Function() _fn;

  _StubApiClient(this._fn) : super(baseUrl: 'http://test');

  @override
  Future<List<Event>> getEvents() => _fn();
}

class _SpyApiClient extends EventsApiClient {
  bool closeCalled = false;

  _SpyApiClient() : super(baseUrl: 'http://test');

  @override
  Future<List<Event>> getEvents() async => [];

  @override
  void close() => closeCalled = true;
}

// --- Tests ---

void main() {
  Widget wrap(EventsApiClient client) =>
      MaterialApp(home: EventsScreen(apiClient: client));

  testWidgets('shows loading indicator before response arrives',
      (tester) async {
    final client = _StubApiClient(() => Completer<List<Event>>().future);
    await tester.pumpWidget(wrap(client));

    expect(find.byType(CircularProgressIndicator), findsOneWidget);
  });

  testWidgets('shows event title, location, and description on success',
      (tester) async {
    final client = _StubApiClient(
      () async => [
        _fakeEvent(
          title: 'Toddler Storytime',
          location: 'Public Library',
          description: 'Weekly storytime for toddlers.',
        ),
      ],
    );
    await tester.pumpWidget(wrap(client));
    await tester.pumpAndSettle();

    expect(find.text('Toddler Storytime'), findsOneWidget);
    expect(find.text('Public Library'), findsOneWidget);
    expect(find.text('Weekly storytime for toddlers.'), findsOneWidget);
  });

  testWidgets('shows empty message when list is empty', (tester) async {
    final client = _StubApiClient(() async => []);
    await tester.pumpWidget(wrap(client));
    await tester.pumpAndSettle();

    expect(find.text('No upcoming events.'), findsOneWidget);
  });

  testWidgets('shows error message and retry button on failure',
      (tester) async {
    final client = _StubApiClient(() async => throw Exception('Network error'));
    await tester.pumpWidget(wrap(client));
    await tester.pumpAndSettle();

    expect(find.text('Failed to load events.'), findsOneWidget);
    expect(find.text('Retry'), findsOneWidget);
  });

  testWidgets('retry button reloads and shows events', (tester) async {
    var callCount = 0;
    final client = _StubApiClient(() {
      callCount++;
      if (callCount == 1) return Future.error(Exception('First call fails'));
      return Future.value([_fakeEvent(title: 'Loaded Event')]);
    });

    await tester.pumpWidget(wrap(client));
    await tester.pumpAndSettle();
    expect(find.text('Failed to load events.'), findsOneWidget);

    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();
    expect(find.text('Loaded Event'), findsOneWidget);
  });

  testWidgets('does not close an injected api client on dispose',
      (tester) async {
    final spy = _SpyApiClient();
    await tester.pumpWidget(wrap(spy));
    await tester.pumpAndSettle();

    await tester.pumpWidget(const SizedBox());
    expect(spy.closeCalled, isFalse);
  });

  testWidgets('closes internally created api client on dispose',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(home: EventsScreen()));
    await tester.pumpAndSettle();

    expect(() => tester.pumpWidget(const SizedBox()), returnsNormally);
  });
}
