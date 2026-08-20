import 'dart:convert';

import 'package:http/http.dart' as http;

import 'package:vilvia/core/constants/api_constants.dart';
import 'package:vilvia/features/events/data/event.dart';

class EventsApiClient {
  final http.Client _client;
  final String _baseUrl;
  final bool _ownsClient;
  final String? Function()? _accessToken;

  /// [accessToken] is only required for [createEvent] -- [getEvents] is
  /// public and never sends an Authorization header, so it's fine to
  /// construct this client without one when only browsing is needed.
  EventsApiClient({
    http.Client? client,
    String? baseUrl,
    this._accessToken,
  })  : _client = client ?? http.Client(),
        _ownsClient = client == null,
        _baseUrl = baseUrl ?? apiBaseUrl;

  void close() {
    if (_ownsClient) _client.close();
  }

  Map<String, String> _authHeaders() {
    final token = _accessToken?.call();
    if (token == null) {
      throw StateError(
        'No active session; cannot call an authenticated endpoint.',
      );
    }
    return {'Authorization': 'Bearer $token'};
  }

  Future<List<Event>> getEvents() async {
    final response = await _client.get(Uri.parse('$_baseUrl/events'));

    if (response.statusCode != 200) {
      throw Exception('Failed to load events: ${response.statusCode}');
    }

    final decoded = jsonDecode(response.body);
    if (decoded is! List) {
      throw Exception('Invalid response: expected a JSON list');
    }

    return decoded.cast<Map<String, dynamic>>().map(Event.fromJson).toList();
  }

  /// Admin-only (enforced server-side by `require_admin` on `POST
  /// /events`, not by anything in this client). Creates a draft Event --
  /// the backend always sets `is_published = false` and `created_by`
  /// from the authenticated admin's own Profile; neither field is ever
  /// sent from here, and there is no parameter to set them.
  ///
  /// [startsAt]/[endsAt] are always sent as UTC ISO-8601 (a trailing
  /// `Z`), regardless of the device's local timezone, since the backend
  /// requires timezone-aware datetimes.
  Future<Event> createEvent({
    required String title,
    required String description,
    required String location,
    required DateTime startsAt,
    DateTime? endsAt,
  }) async {
    final response = await _client.post(
      Uri.parse('$_baseUrl/events'),
      headers: {..._authHeaders(), 'Content-Type': 'application/json'},
      body: jsonEncode({
        'title': title,
        'description': description,
        'location': location,
        'starts_at': startsAt.toUtc().toIso8601String(),
        if (endsAt != null) 'ends_at': endsAt.toUtc().toIso8601String(),
      }),
    );

    if (response.statusCode != 201) {
      throw Exception('Failed to create event: ${response.statusCode}');
    }

    return Event.fromJson(jsonDecode(response.body) as Map<String, dynamic>);
  }

  /// Admin-only (enforced server-side by `require_admin`). Every
  /// unpublished (draft) Event, newest-created first -- includes
  /// past-dated drafts, since [publishEvent] rejects those rather than
  /// this listing hiding them.
  Future<List<Event>> getDraftEvents() async {
    final response = await _client.get(
      Uri.parse('$_baseUrl/events/drafts'),
      headers: _authHeaders(),
    );

    if (response.statusCode != 200) {
      throw Exception('Failed to load draft events: ${response.statusCode}');
    }

    final decoded = jsonDecode(response.body);
    if (decoded is! List) {
      throw Exception('Invalid response: expected a JSON list');
    }

    return decoded.cast<Map<String, dynamic>>().map(Event.fromJson).toList();
  }

  /// Admin-only (enforced server-side by `require_admin`). Publishes a
  /// draft Event, making it eligible to appear in the public [getEvents]
  /// list. Sends no request body -- there is nothing for the client to
  /// set here beyond which Event to publish (the id, in the path).
  ///
  /// Idempotent for an already-published, still-upcoming Event (the
  /// backend returns 200 again). Rejected with 409 if the Event's start
  /// time has already passed -- see the thrown message.
  Future<Event> publishEvent(String id) async {
    final response = await _client.post(
      Uri.parse('$_baseUrl/events/$id/publish'),
      headers: _authHeaders(),
    );

    if (response.statusCode == 409) {
      throw Exception(
        "This event's start time has already passed and can no longer "
        'be published.',
      );
    }
    if (response.statusCode != 200) {
      throw Exception('Failed to publish event: ${response.statusCode}');
    }

    return Event.fromJson(jsonDecode(response.body) as Map<String, dynamic>);
  }
}
