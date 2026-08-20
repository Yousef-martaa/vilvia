import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:vilvia/features/events/data/event.dart';
import 'package:vilvia/features/events/data/events_api_client.dart';
import 'package:vilvia/features/events/presentation/screens/draft_events_screen.dart';

Event _fakeEvent({
  String id = '1',
  String title = 'Draft Event',
  String location = 'Community Centre',
  String description = 'A short description',
}) {
  final start = DateTime.now().toUtc().add(const Duration(days: 1));
  return Event(
    id: id,
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
  _StubApiClient({
    required this.getDrafts,
    this.publish,
  }) : super(baseUrl: 'http://test');

  final Future<List<Event>> Function() getDrafts;
  final Future<Event> Function(String id)? publish;

  int publishCallCount = 0;
  String? lastPublishedId;

  @override
  Future<List<Event>> getDraftEvents() => getDrafts();

  @override
  Future<Event> publishEvent(String id) {
    publishCallCount++;
    lastPublishedId = id;
    return publish!(id);
  }
}

void main() {
  Widget wrap(EventsApiClient client) =>
      MaterialApp(home: DraftEventsScreen(apiClient: client));

  testWidgets('shows loading indicator before response arrives',
      (tester) async {
    final client = _StubApiClient(getDrafts: () => Completer<List<Event>>().future);
    await tester.pumpWidget(wrap(client));

    expect(find.byType(CircularProgressIndicator), findsOneWidget);
  });

  testWidgets('shows draft events on success', (tester) async {
    final client = _StubApiClient(
      getDrafts: () async => [_fakeEvent(title: 'Toddler Storytime')],
    );
    await tester.pumpWidget(wrap(client));
    await tester.pumpAndSettle();

    expect(find.text('Toddler Storytime'), findsOneWidget);
    expect(find.text('Publish'), findsOneWidget);
  });

  testWidgets('shows empty message when there are no drafts', (tester) async {
    final client = _StubApiClient(getDrafts: () async => []);
    await tester.pumpWidget(wrap(client));
    await tester.pumpAndSettle();

    expect(find.text('No draft events.'), findsOneWidget);
  });

  testWidgets('shows error message and retry button on load failure',
      (tester) async {
    final client = _StubApiClient(
      getDrafts: () async => throw Exception('Network error'),
    );
    await tester.pumpWidget(wrap(client));
    await tester.pumpAndSettle();

    expect(find.text('Failed to load draft events.'), findsOneWidget);
    expect(find.text('Retry'), findsOneWidget);
  });

  testWidgets('retry button reloads and shows drafts', (tester) async {
    var callCount = 0;
    final client = _StubApiClient(
      getDrafts: () {
        callCount++;
        if (callCount == 1) return Future.error(Exception('First call fails'));
        return Future.value([_fakeEvent(title: 'Loaded Draft')]);
      },
    );

    await tester.pumpWidget(wrap(client));
    await tester.pumpAndSettle();
    expect(find.text('Failed to load draft events.'), findsOneWidget);

    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();
    expect(find.text('Loaded Draft'), findsOneWidget);
  });

  testWidgets(
      'tapping Publish calls publishEvent with the event id, removes it '
      'from the list, and shows a confirmation', (tester) async {
    final client = _StubApiClient(
      getDrafts: () async => [_fakeEvent(id: 'evt-1', title: 'Playgroup')],
      publish: (id) async => _fakeEvent(id: id, title: 'Playgroup'),
    );

    await tester.pumpWidget(wrap(client));
    await tester.pumpAndSettle();
    expect(find.text('Playgroup'), findsOneWidget);

    await tester.tap(find.text('Publish'));
    await tester.pumpAndSettle();

    expect(client.publishCallCount, 1);
    expect(client.lastPublishedId, 'evt-1');
    expect(find.text('Playgroup'), findsNothing);
    expect(find.textContaining('published'), findsOneWidget);
  });

  testWidgets(
      'a failed publish shows an error and keeps the draft in the list',
      (tester) async {
    final client = _StubApiClient(
      getDrafts: () async => [_fakeEvent(id: 'evt-1', title: 'Playgroup')],
      publish: (id) async => throw Exception(
        "This event's start time has already passed and can no longer "
        'be published.',
      ),
    );

    await tester.pumpWidget(wrap(client));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Publish'));
    await tester.pumpAndSettle();

    expect(find.text('Playgroup'), findsOneWidget);
    expect(find.textContaining('already passed'), findsOneWidget);
  });
}
