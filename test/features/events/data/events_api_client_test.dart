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

  group('EventsApiClient.createEvent', () {
    test('sends POST /events with the bearer token and parses the 201 '
        'response', () async {
      http.Request? captured;
      final client = MockClient((request) async {
        captured = request;
        return http.Response(jsonEncode(eventJson(title: 'Created Event')), 201);
      });
      final api = EventsApiClient(
        client: client,
        baseUrl: testBaseUrl,
        accessToken: () => 'test-token',
      );

      final event = await api.createEvent(
        title: 'Created Event',
        description: 'A short description',
        location: 'Community Centre',
        startsAt: DateTime.utc(2026, 8, 22, 10),
        endsAt: DateTime.utc(2026, 8, 22, 12),
      );

      expect(event.title, 'Created Event');
      expect(captured!.method, 'POST');
      expect(captured!.url.path, '/events');
      expect(captured!.headers['Authorization'], 'Bearer test-token');
    });

    test('request body contains only the allowed fields', () async {
      http.Request? captured;
      final client = MockClient((request) async {
        captured = request;
        return http.Response(jsonEncode(eventJson()), 201);
      });
      final api = EventsApiClient(
        client: client,
        baseUrl: testBaseUrl,
        accessToken: () => 'test-token',
      );

      await api.createEvent(
        title: 'Created Event',
        description: 'A short description',
        location: 'Community Centre',
        startsAt: DateTime.utc(2026, 8, 22, 10),
        endsAt: DateTime.utc(2026, 8, 22, 12),
      );

      final body = jsonDecode(captured!.body) as Map<String, dynamic>;
      expect(
        body.keys.toSet(),
        {'title', 'description', 'location', 'starts_at', 'ends_at'},
      );
      expect(body.containsKey('id'), isFalse);
      expect(body.containsKey('created_by'), isFalse);
      expect(body.containsKey('is_published'), isFalse);
      expect(body.containsKey('role'), isFalse);
    });

    test('omits ends_at entirely when not provided', () async {
      http.Request? captured;
      final client = MockClient((request) async {
        captured = request;
        return http.Response(jsonEncode(eventJson()), 201);
      });
      final api = EventsApiClient(
        client: client,
        baseUrl: testBaseUrl,
        accessToken: () => 'test-token',
      );

      await api.createEvent(
        title: 'Created Event',
        description: 'A short description',
        location: 'Community Centre',
        startsAt: DateTime.utc(2026, 8, 22, 10),
      );

      final body = jsonDecode(captured!.body) as Map<String, dynamic>;
      expect(body.containsKey('ends_at'), isFalse);
    });

    test('serializes starts_at/ends_at as UTC ISO-8601 with a trailing Z, '
        'even from a local (non-UTC) DateTime', () async {
      http.Request? captured;
      final client = MockClient((request) async {
        captured = request;
        return http.Response(jsonEncode(eventJson()), 201);
      });
      final api = EventsApiClient(
        client: client,
        baseUrl: testBaseUrl,
        accessToken: () => 'test-token',
      );

      await api.createEvent(
        title: 'Created Event',
        description: 'A short description',
        location: 'Community Centre',
        startsAt: DateTime(2026, 8, 22, 10),
        endsAt: DateTime(2026, 8, 22, 12),
      );

      final body = jsonDecode(captured!.body) as Map<String, dynamic>;
      expect(body['starts_at'], endsWith('Z'));
      expect(body['ends_at'], endsWith('Z'));
    });

    test('throws on a non-201 response', () async {
      final client = MockClient(
        (_) async => http.Response('Forbidden', 403),
      );
      final api = EventsApiClient(
        client: client,
        baseUrl: testBaseUrl,
        accessToken: () => 'test-token',
      );

      expect(
        api.createEvent(
          title: 'Created Event',
          description: 'A short description',
          location: 'Community Centre',
          startsAt: DateTime.utc(2026, 8, 22, 10),
        ),
        throwsException,
      );
    });

    test('throws StateError when no access token is available', () async {
      final client = MockClient(
        (_) async => http.Response(jsonEncode(eventJson()), 201),
      );
      final api = EventsApiClient(
        client: client,
        baseUrl: testBaseUrl,
        accessToken: () => null,
      );

      expect(
        api.createEvent(
          title: 'Created Event',
          description: 'A short description',
          location: 'Community Centre',
          startsAt: DateTime.utc(2026, 8, 22, 10),
        ),
        throwsStateError,
      );
    });
  });

  group('EventsApiClient.getDraftEvents', () {
    test('sends GET /events/drafts with the bearer token and parses the '
        'response', () async {
      http.Request? captured;
      final client = MockClient((request) async {
        captured = request;
        return http.Response(jsonEncode([eventJson(title: 'Draft Event')]), 200);
      });
      final api = EventsApiClient(
        client: client,
        baseUrl: testBaseUrl,
        accessToken: () => 'test-token',
      );

      final drafts = await api.getDraftEvents();

      expect(drafts.length, 1);
      expect(drafts[0].title, 'Draft Event');
      expect(captured!.method, 'GET');
      expect(captured!.url.path, '/events/drafts');
      expect(captured!.headers['Authorization'], 'Bearer test-token');
    });

    test('returns empty list for empty response', () async {
      final client = MockClient((_) async => http.Response('[]', 200));
      final api = EventsApiClient(
        client: client,
        baseUrl: testBaseUrl,
        accessToken: () => 'test-token',
      );

      final drafts = await api.getDraftEvents();

      expect(drafts, isEmpty);
    });

    test('throws on non-200 response', () async {
      final client = MockClient((_) async => http.Response('Forbidden', 403));
      final api = EventsApiClient(
        client: client,
        baseUrl: testBaseUrl,
        accessToken: () => 'test-token',
      );

      expect(api.getDraftEvents(), throwsException);
    });

    test('throws StateError when no access token is available', () async {
      final client = MockClient((_) async => http.Response('[]', 200));
      final api = EventsApiClient(
        client: client,
        baseUrl: testBaseUrl,
        accessToken: () => null,
      );

      expect(api.getDraftEvents(), throwsStateError);
    });
  });

  group('EventsApiClient.publishEvent', () {
    test('sends POST /events/{id}/publish with the bearer token and parses '
        'the response', () async {
      http.Request? captured;
      final client = MockClient((request) async {
        captured = request;
        return http.Response(jsonEncode(eventJson(title: 'Published Event')), 200);
      });
      final api = EventsApiClient(
        client: client,
        baseUrl: testBaseUrl,
        accessToken: () => 'test-token',
      );

      final event = await api.publishEvent('123e4567-e89b-12d3-a456-426614174000');

      expect(event.title, 'Published Event');
      expect(captured!.method, 'POST');
      expect(
        captured!.url.path,
        '/events/123e4567-e89b-12d3-a456-426614174000/publish',
      );
      expect(captured!.headers['Authorization'], 'Bearer test-token');
    });

    test('sends no request body', () async {
      http.Request? captured;
      final client = MockClient((request) async {
        captured = request;
        return http.Response(jsonEncode(eventJson()), 200);
      });
      final api = EventsApiClient(
        client: client,
        baseUrl: testBaseUrl,
        accessToken: () => 'test-token',
      );

      await api.publishEvent('1');

      expect(captured!.body, isEmpty);
    });

    test('throws a descriptive error on a 409 (past starts_at) response',
        () async {
      final client = MockClient((_) async => http.Response('Conflict', 409));
      final api = EventsApiClient(
        client: client,
        baseUrl: testBaseUrl,
        accessToken: () => 'test-token',
      );

      expect(
        api.publishEvent('1'),
        throwsA(
          predicate((e) => e.toString().contains('already passed')),
        ),
      );
    });

    test('throws on a 404 response', () async {
      final client = MockClient((_) async => http.Response('Not Found', 404));
      final api = EventsApiClient(
        client: client,
        baseUrl: testBaseUrl,
        accessToken: () => 'test-token',
      );

      expect(api.publishEvent('1'), throwsException);
    });

    test('throws on a 403 response', () async {
      final client = MockClient((_) async => http.Response('Forbidden', 403));
      final api = EventsApiClient(
        client: client,
        baseUrl: testBaseUrl,
        accessToken: () => 'test-token',
      );

      expect(api.publishEvent('1'), throwsException);
    });

    test('throws StateError when no access token is available', () async {
      final client = MockClient(
        (_) async => http.Response(jsonEncode(eventJson()), 200),
      );
      final api = EventsApiClient(
        client: client,
        baseUrl: testBaseUrl,
        accessToken: () => null,
      );

      expect(api.publishEvent('1'), throwsStateError);
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
