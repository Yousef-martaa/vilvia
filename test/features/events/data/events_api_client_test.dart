import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:vilvia/features/events/data/events_api_client.dart';

class _TrackingClient extends http.BaseClient {
  bool closeCalled = false;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    throw UnsupportedError('not used in close tests');
  }

  @override
  void close() {
    closeCalled = true;
    super.close();
  }
}

void main() {
  const testBaseUrl = 'http://localhost';

  Map<String, dynamic> eventJson({String title = 'Test Event'}) => {
        'id': '123e4567-e89b-12d3-a456-426614174000',
        'title': title,
        'description': 'A short description',
        'location': 'Community Centre',
        'starts_at': '2026-08-22T10:00:00+02:00',
        'ends_at': '2026-08-22T12:00:00+02:00',
        'created_at': '2024-01-01T00:00:00Z',
        'updated_at': '2024-01-01T00:00:00Z',
      };

  group('EventsApiClient.getEvents', () {
    test('parses a successful response', () async {
      final client = MockClient(
        (_) async => http.Response(jsonEncode([eventJson()]), 200),
      );
      final api = EventsApiClient(client: client, baseUrl: testBaseUrl);

      final events = await api.getEvents();

      expect(events.length, 1);
      expect(events[0].title, 'Test Event');
      expect(events[0].location, 'Community Centre');
      expect(events[0].endsAt, isNotNull);
    });

    test('parses a response with a null ends_at', () async {
      final json = eventJson()..['ends_at'] = null;
      final client = MockClient(
        (_) async => http.Response(jsonEncode([json]), 200),
      );
      final api = EventsApiClient(client: client, baseUrl: testBaseUrl);

      final events = await api.getEvents();

      expect(events[0].endsAt, isNull);
    });

    test('returns empty list for empty response', () async {
      final client = MockClient((_) async => http.Response('[]', 200));
      final api = EventsApiClient(client: client, baseUrl: testBaseUrl);

      final events = await api.getEvents();

      expect(events, isEmpty);
    });

    test('throws on non-200 response', () async {
      final client = MockClient(
        (_) async => http.Response('Internal Server Error', 500),
      );
      final api = EventsApiClient(client: client, baseUrl: testBaseUrl);

      expect(api.getEvents(), throwsException);
    });

    test('throws on invalid JSON shape (not a list)', () async {
      final client = MockClient(
        (_) async => http.Response(jsonEncode({'error': 'bad'}), 200),
      );
      final api = EventsApiClient(client: client, baseUrl: testBaseUrl);

      expect(api.getEvents(), throwsException);
    });
  });

  group('EventsApiClient.close', () {
    test('does not close an injected client', () {
      final tracking = _TrackingClient();
      final api = EventsApiClient(client: tracking, baseUrl: testBaseUrl);
      api.close();
      expect(tracking.closeCalled, isFalse);
    });

    test('does not throw when client was created internally', () {
      final api = EventsApiClient(baseUrl: testBaseUrl);
      expect(api.close, returnsNormally);
    });
  });
}
