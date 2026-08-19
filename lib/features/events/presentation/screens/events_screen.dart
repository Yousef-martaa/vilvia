import 'dart:async';

import 'package:flutter/material.dart';

import 'package:vilvia/features/auth/data/auth_service.dart';
import 'package:vilvia/features/auth/data/profile.dart';
import 'package:vilvia/features/auth/data/profile_api_client.dart';
import 'package:vilvia/features/events/data/event.dart';
import 'package:vilvia/features/events/data/events_api_client.dart';
import 'package:vilvia/features/events/presentation/screens/create_event_screen.dart';
import 'package:vilvia/features/events/presentation/widgets/event_card.dart';
import 'package:vilvia/theme/vilvia_colors.dart';

/// The Events screen (Issue #63): lists published, upcoming events from
/// Vilvia's own API, soonest first. No filtering/search, no details
/// screen, no booking -- browsing only.
///
/// Issue #75 added one admin-only addition: a "New Event" entry point,
/// shown only when the caller's own `Profile` (freshly read from `GET
/// /me`, never cached/trusted from anywhere else) has `role ==
/// UserRole.admin`. This is a UI convenience only -- `POST /events`
/// remains independently protected by `require_admin` server-side, so
/// hiding/showing this button changes nothing about who can actually
/// create an Event.
class EventsScreen extends StatefulWidget {
  final EventsApiClient? apiClient;
  final AuthService? authService;
  final ProfileApiClient? profileApiClient;

  const EventsScreen({
    super.key,
    this.apiClient,
    this.authService,
    this.profileApiClient,
  });

  @override
  State<EventsScreen> createState() => _EventsScreenState();
}

class _EventsScreenState extends State<EventsScreen> {
  late final EventsApiClient _apiClient;
  late final bool _ownsClient;
  late final AuthService _authService;
  late final ProfileApiClient _profileApiClient;
  late final bool _ownsProfileClient;
  late final StreamSubscription _authSubscription;

  List<Event>? _events;
  bool _isLoading = true;
  String? _error;
  bool _isAdmin = false;

  @override
  void initState() {
    super.initState();
    _authService = widget.authService ?? AuthService();

    _ownsProfileClient = widget.profileApiClient == null;
    _profileApiClient = widget.profileApiClient ??
        ProfileApiClient(
          accessToken: () => _authService.currentSession?.accessToken,
        );

    _ownsClient = widget.apiClient == null;
    _apiClient = widget.apiClient ??
        EventsApiClient(
          accessToken: () => _authService.currentSession?.accessToken,
        );

    _loadEvents();

    // Re-evaluated on every auth-state change (not just once at open) so
    // the admin entry point never goes stale for as long as this screen
    // stays open -- e.g. an admin who signs out here loses the button
    // immediately, without needing to reopen the screen.
    _checkAdminStatus();
    try {
      _authSubscription =
          _authService.onAuthStateChange.listen((_) => _checkAdminStatus());
    } catch (_) {
      // Auth isn't configured in this environment (e.g. some test
      // setups) -- admin status was already resolved once above (and
      // fails closed); there's just nothing further to react to.
      _authSubscription = const Stream<void>.empty().listen((_) {});
    }
  }

  @override
  void dispose() {
    _authSubscription.cancel();
    if (_ownsClient) _apiClient.close();
    if (_ownsProfileClient) _profileApiClient.close();
    super.dispose();
  }

  Future<void> _checkAdminStatus() async {
    final isAdmin = await _resolveIsAdmin();
    if (!mounted) return;
    setState(() => _isAdmin = isAdmin);
  }

  /// Fails closed on anything -- no session, a Profile that doesn't
  /// exist yet, a network error, or (in test/dev environments) Supabase
  /// never having been initialized. None of those should ever be read
  /// as "admin"; they should just hide the button.
  Future<bool> _resolveIsAdmin() async {
    try {
      final session = _authService.currentSession;
      if (session == null) return false;
      final profile = await _profileApiClient.getMe();
      return profile.role == UserRole.admin;
    } catch (_) {
      return false;
    }
  }

  Future<void> _loadEvents() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final events = await _apiClient.getEvents();
      if (!mounted) return;
      setState(() {
        _events = events;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _isLoading = false;
      });
    }
  }

  void _openCreateEvent() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => CreateEventScreen(apiClient: _apiClient),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return Scaffold(
      floatingActionButton: _isAdmin
          ? FloatingActionButton.extended(
              onPressed: _openCreateEvent,
              icon: const Icon(Icons.add),
              label: const Text('New Event'),
            )
          : null,
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 24, 20, 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Events', style: textTheme.headlineLarge),
                      const SizedBox(height: 8),
                      Text(
                        'Upcoming events and meetups for parents and '
                        'families.',
                        style: textTheme.bodyLarge
                            ?.copyWith(color: VilviaColors.gray),
                      ),
                    ],
                  ),
                ),
                Expanded(child: _buildBody(textTheme)),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildBody(TextTheme textTheme) {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_error != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              'Failed to load events.',
              style: textTheme.bodyLarge?.copyWith(color: VilviaColors.gray),
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: _loadEvents,
              child: const Text('Retry'),
            ),
          ],
        ),
      );
    }

    final events = _events ?? [];
    if (events.isEmpty) {
      return Center(
        child: Text(
          'No upcoming events.',
          style: textTheme.bodyLarge?.copyWith(color: VilviaColors.gray),
        ),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
      itemCount: events.length,
      separatorBuilder: (_, _) => const SizedBox(height: 12),
      itemBuilder: (context, index) => EventCard(event: events[index]),
    );
  }
}
