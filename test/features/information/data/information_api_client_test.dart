import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:vilvia/features/information/data/information_api_client.dart';

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

  Map<String, dynamic> resourceJson({String title = 'Test Resource'}) => {
        'id': '123e4567-e89b-12d3-a456-426614174000',
        'title': title,
        'summary': 'A short summary',
        'category': 'child_development',
        'stage': 'pregnancy',
        'source_name': 'Health Authority',
        'source_url': 'https://example.com',
        'created_at': '2024-01-01T00:00:00Z',
        'updated_at': '2024-01-01T00:00:00Z',
      };

  group('InformationApiClient.getResources', () {
    test('parses a successful response', () async {
      final client = MockClient(
        (_) async => http.Response(jsonEncode([resourceJson()]), 200),
      );
      final api = InformationApiClient(client: client, baseUrl: testBaseUrl);

      final resources = await api.getResources();

      expect(resources.length, 1);
      expect(resources[0].title, 'Test Resource');
      expect(resources[0].sourceName, 'Health Authority');
      expect(resources[0].category, 'child_development');
    });

    test('returns empty list for empty response', () async {
      final client = MockClient((_) async => http.Response('[]', 200));
      final api = InformationApiClient(client: client, baseUrl: testBaseUrl);

      final resources = await api.getResources();

      expect(resources, isEmpty);
    });

    test('throws on non-200 response', () async {
      final client = MockClient(
        (_) async => http.Response('Internal Server Error', 500),
      );
      final api = InformationApiClient(client: client, baseUrl: testBaseUrl);

      expect(api.getResources(), throwsException);
    });

    test('throws on invalid JSON shape (not a list)', () async {
      final client = MockClient(
        (_) async => http.Response(jsonEncode({'error': 'bad'}), 200),
      );
      final api = InformationApiClient(client: client, baseUrl: testBaseUrl);

      expect(api.getResources(), throwsException);
    });
  });

  Map<String, dynamic> resourceDetailJson({String body = 'The full body.'}) => {
        ...resourceJson(),
        'body': body,
      };

  group('InformationApiClient.getResource', () {
    test('parses a successful response including the body', () async {
      final client = MockClient(
        (request) async {
          expect(request.url.path, '/resources/abc-123');
          return http.Response(jsonEncode(resourceDetailJson()), 200);
        },
      );
      final api = InformationApiClient(client: client, baseUrl: testBaseUrl);

      final detail = await api.getResource('abc-123');

      expect(detail.resource.title, 'Test Resource');
      expect(detail.resource.sourceName, 'Health Authority');
      expect(detail.body, 'The full body.');
    });

    test('throws on 404 (not found or unpublished)', () async {
      final client = MockClient(
        (_) async => http.Response('Not Found', 404),
      );
      final api = InformationApiClient(client: client, baseUrl: testBaseUrl);

      expect(api.getResource('missing-id'), throwsException);
    });

    test('throws on non-200 response', () async {
      final client = MockClient(
        (_) async => http.Response('Internal Server Error', 500),
      );
      final api = InformationApiClient(client: client, baseUrl: testBaseUrl);

      expect(api.getResource('abc-123'), throwsException);
    });

    test('throws on invalid JSON shape (not an object)', () async {
      final client = MockClient(
        (_) async => http.Response(jsonEncode([1, 2, 3]), 200),
      );
      final api = InformationApiClient(client: client, baseUrl: testBaseUrl);

      expect(api.getResource('abc-123'), throwsException);
    });
  });

  group('InformationApiClient.close', () {
    test('does not close an injected client', () {
      final tracking = _TrackingClient();
      final api = InformationApiClient(client: tracking, baseUrl: testBaseUrl);
      api.close();
      expect(tracking.closeCalled, isFalse);
    });

    test('does not throw when client was created internally', () {
      final api = InformationApiClient(baseUrl: testBaseUrl);
      expect(api.close, returnsNormally);
    });
  });
}
