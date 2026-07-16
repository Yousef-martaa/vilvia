import 'dart:convert';

import 'package:http/http.dart' as http;

import 'package:vilvia/core/constants/api_constants.dart';
import 'package:vilvia/features/information/data/resource.dart';

class InformationApiClient {
  final http.Client _client;
  final String _baseUrl;
  final bool _ownsClient;

  InformationApiClient({
    http.Client? client,
    String? baseUrl,
  })  : _client = client ?? http.Client(),
        _ownsClient = client == null,
        _baseUrl = baseUrl ?? apiBaseUrl;

  void close() {
    if (_ownsClient) _client.close();
  }

  Future<List<Resource>> getResources() async {
    final response = await _client.get(Uri.parse('$_baseUrl/resources'));

    if (response.statusCode != 200) {
      throw Exception('Failed to load resources: ${response.statusCode}');
    }

    final decoded = jsonDecode(response.body);
    if (decoded is! List) {
      throw Exception('Invalid response: expected a JSON list');
    }

    return decoded
        .cast<Map<String, dynamic>>()
        .map(Resource.fromJson)
        .toList();
  }
}
