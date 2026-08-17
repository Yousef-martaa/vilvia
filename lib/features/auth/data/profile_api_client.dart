import 'dart:convert';

import 'package:http/http.dart' as http;

import 'package:vilvia/core/constants/api_constants.dart';
import 'package:vilvia/features/auth/data/profile.dart';

/// Raised by [ProfileApiClient.getMe] specifically when the authenticated
/// caller has no Profile yet (backend 404) -- distinct from other
/// failures so callers can offer to bootstrap one, rather than just
/// showing a generic error.
class ProfileNotFoundException implements Exception {}

class ProfileApiClient {
  final http.Client _client;
  final String _baseUrl;
  final bool _ownsClient;
  final String? Function() _accessToken;

  ProfileApiClient({
    http.Client? client,
    String? baseUrl,
    required this._accessToken,
  })  : _client = client ?? http.Client(),
        _ownsClient = client == null,
        _baseUrl = baseUrl ?? apiBaseUrl;

  void close() {
    if (_ownsClient) _client.close();
  }

  Map<String, String> _authHeaders() {
    final token = _accessToken();
    if (token == null) {
      throw StateError(
        'No active session; cannot call an authenticated endpoint.',
      );
    }
    return {'Authorization': 'Bearer $token'};
  }

  Future<Profile> getMe() async {
    final response = await _client.get(
      Uri.parse('$_baseUrl/me'),
      headers: _authHeaders(),
    );

    if (response.statusCode == 404) {
      throw ProfileNotFoundException();
    }
    if (response.statusCode != 200) {
      throw Exception('Failed to load profile: ${response.statusCode}');
    }

    return Profile.fromJson(jsonDecode(response.body) as Map<String, dynamic>);
  }

  Future<Profile> bootstrap({required String firstName}) async {
    final response = await _client.post(
      Uri.parse('$_baseUrl/me/bootstrap'),
      headers: {..._authHeaders(), 'Content-Type': 'application/json'},
      body: jsonEncode({'first_name': firstName}),
    );

    if (response.statusCode != 200) {
      throw Exception('Failed to set up profile: ${response.statusCode}');
    }

    return Profile.fromJson(jsonDecode(response.body) as Map<String, dynamic>);
  }
}
