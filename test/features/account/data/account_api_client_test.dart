import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:vilvia/features/account/data/account_api_client.dart';

void main() {
  const baseUrl = 'http://localhost';

  for (final entry in {
    'requested': AccountDeletionStatus.requested,
    'auth_deleted': AccountDeletionStatus.authDeleted,
    'completed': AccountDeletionStatus.completed,
  }.entries) {
    test('POSTs empty authenticated request and parses ${entry.key}', () async {
      var calls = 0;
      final api = AccountApiClient(
        baseUrl: baseUrl,
        accessTokenProvider: () => 'access-token',
        client: MockClient((request) async {
          calls++;
          expect(request.method, 'POST');
          expect(request.url.path, '/me/account-deletion-request');
          expect(request.headers['Authorization'], 'Bearer access-token');
          expect(request.bodyBytes, isEmpty);
          return http.Response(
            jsonEncode({
              'status': entry.key,
              'requested_at': '2026-09-03T10:00:00Z',
            }),
            202,
          );
        }),
      );

      final result = await api.requestAccountDeletion();

      expect(calls, 1);
      expect(result.status, entry.value);
      expect(result.requestedAt, DateTime.utc(2026, 9, 3, 10));
    });
  }

  test('fails locally without an authenticated session', () async {
    var called = false;
    final api = AccountApiClient(
      baseUrl: baseUrl,
      accessTokenProvider: () => null,
      client: MockClient((_) async {
        called = true;
        return http.Response('', 202);
      }),
    );
    await expectLater(api.requestAccountDeletion(), throwsStateError);
    expect(called, isFalse);
  });

  test('rejects malformed 202 responses', () async {
    for (final body in [
      '{}',
      '{"status":"unknown","requested_at":"2026-09-03T10:00:00Z"}',
      '{"status":"requested","requested_at":"bad"}',
      '{"status":"requested","requested_at":"2026-09-03T10:00:00Z","extra":1}',
      '[]',
    ]) {
      final api = AccountApiClient(
        baseUrl: baseUrl,
        accessTokenProvider: () => 'token',
        client: MockClient((_) async => http.Response(body, 202)),
      );
      await expectLater(api.requestAccountDeletion(), throwsA(anything));
    }
  });

  test('rejects non-202 responses', () async {
    final api = AccountApiClient(
      baseUrl: baseUrl,
      accessTokenProvider: () => 'token',
      client: MockClient((_) async => http.Response('{"detail":"no"}', 409)),
    );
    await expectLater(api.requestAccountDeletion(), throwsException);
  });

  test('times out and a later retry can succeed', () async {
    var calls = 0;
    final api = AccountApiClient(
      baseUrl: baseUrl,
      accessTokenProvider: () => 'token',
      requestTimeout: const Duration(milliseconds: 10),
      client: MockClient((_) async {
        calls++;
        if (calls == 1) {
          await Future<void>.delayed(const Duration(milliseconds: 30));
        }
        return http.Response(
          '{"status":"requested","requested_at":"2026-09-03T10:00:00Z"}',
          202,
        );
      }),
    );

    await expectLater(
      api.requestAccountDeletion(),
      throwsA(isA<TimeoutException>()),
    );
    final result = await api.requestAccountDeletion();
    expect(result.status, AccountDeletionStatus.requested);
    expect(calls, 2);
  });
}
