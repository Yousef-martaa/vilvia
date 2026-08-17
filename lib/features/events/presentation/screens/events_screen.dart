import 'package:flutter/material.dart';

import 'package:vilvia/features/events/data/event.dart';
import 'package:vilvia/features/events/data/events_api_client.dart';
import 'package:vilvia/features/events/presentation/widgets/event_card.dart';
import 'package:vilvia/theme/vilvia_colors.dart';

/// The Events screen (Issue #63): lists published, upcoming events from
/// Vilvia's own API, soonest first. No filtering/search, no details
/// screen, no booking -- browsing only.
class EventsScreen extends StatefulWidget {
  final EventsApiClient? apiClient;

  const EventsScreen({super.key, this.apiClient});

  @override
  State<EventsScreen> createState() => _EventsScreenState();
}

class _EventsScreenState extends State<EventsScreen> {
  late final EventsApiClient _apiClient;
  late final bool _ownsClient;
  List<Event>? _events;
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _ownsClient = widget.apiClient == null;
    _apiClient = widget.apiClient ?? EventsApiClient();
    _loadEvents();
  }

  @override
  void dispose() {
    if (_ownsClient) _apiClient.close();
    super.dispose();
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

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return Scaffold(
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
