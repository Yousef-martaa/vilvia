import 'dart:convert';

import 'package:http/http.dart' as http;

import 'package:vilvia/core/constants/api_constants.dart';

enum AccountDeletionStatus { requested, authDeleted, completed }

class AccountDeletionRequest {
  const AccountDeletionRequest({
    required this.status,
    required this.requestedAt,
  });

  final AccountDeletionStatus status;
  final DateTime requestedAt;

  factory AccountDeletionRequest.fromJson(Map<String, dynamic> json) {
    if (json.length != 2 ||
        !json.containsKey('status') ||
        !json.containsKey('requested_at')) {
      throw const FormatException('Invalid account deletion response.');
    }
    final rawStatus = json['status'];
    final rawRequestedAt = json['requested_at'];
    if (rawStatus is! String || rawRequestedAt is! String) {
      throw const FormatException('Invalid account deletion response.');
    }
    final status = switch (rawStatus) {
      'requested' => AccountDeletionStatus.requested,
      'auth_deleted' => AccountDeletionStatus.authDeleted,
      'completed' => AccountDeletionStatus.completed,
      _ => throw const FormatException('Invalid account deletion status.'),
    };
    final requestedAt = DateTime.tryParse(rawRequestedAt);
    if (requestedAt == null) {
      throw const FormatException('Invalid account deletion timestamp.');
    }
    return AccountDeletionRequest(status: status, requestedAt: requestedAt);
  }
}

class AccountApiClient {
  AccountApiClient({
    http.Client? client,
    String? baseUrl,
    required String? Function() accessTokenProvider,
    this.requestTimeout = const Duration(seconds: 15),
  }) : _client = client ?? http.Client(),
       _ownsClient = client == null,
       _baseUrl = baseUrl ?? apiBaseUrl,
       _accessToken = accessTokenProvider;

  final http.Client _client;
  final bool _ownsClient;
  final String _baseUrl;
  final String? Function() _accessToken;
  final Duration requestTimeout;

  void close() {
    if (_ownsClient) _client.close();
  }

  Future<AccountDeletionRequest> requestAccountDeletion() async {
    final token = _accessToken();
    if (token == null) {
      throw StateError(
        'No active session; cannot call an authenticated endpoint.',
      );
    }
    final response = await _client
        .post(
          Uri.parse('$_baseUrl/me/account-deletion-request'),
          headers: {'Authorization': 'Bearer $token'},
        )
        .timeout(requestTimeout);
    if (response.statusCode != 202) {
      throw Exception('Account deletion request was not accepted.');
    }
    final decoded = jsonDecode(response.body);
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('Invalid account deletion response.');
    }
    return AccountDeletionRequest.fromJson(decoded);
  }
}
