import 'package:flutter/material.dart';

import 'package:vilvia/features/events/data/event.dart';
import 'package:vilvia/features/events/data/events_api_client.dart';
import 'package:vilvia/features/events/presentation/widgets/event_card.dart';
import 'package:vilvia/theme/vilvia_colors.dart';

/// Admin-only draft-review screen (Issue #77): lists Events created via
/// [CreateEventScreen] (Issue #75) that are still unpublished, and lets
/// an admin publish one. This screen does no role checking of its own --
/// the real, only enforcement is backend `require_admin` on both `GET
/// /events/drafts` and `POST /events/{id}/publish`, which reject a
/// non-admin caller regardless of how this screen was reached.
///
/// Deliberately just a list + one action: no Event Details screen, no
/// edit/delete, no dashboard.
class DraftEventsScreen extends StatefulWidget {
  const DraftEventsScreen({super.key, this.apiClient});

  final EventsApiClient? apiClient;

  @override
  State<DraftEventsScreen> createState() => _DraftEventsScreenState();
}

class _DraftEventsScreenState extends State<DraftEventsScreen> {
  late final EventsApiClient _apiClient;
  late final bool _ownsClient;

  List<Event>? _drafts;
  bool _isLoading = true;
  String? _error;

  // Per-draft state, keyed by Event.id -- a set/map rather than a single
  // screen-wide flag, since publishing one draft must not disable the
  // Publish button on every other draft in the list.
  final Set<String> _publishingIds = {};
  final Map<String, String> _publishErrors = {};

  @override
  void initState() {
    super.initState();
    _ownsClient = widget.apiClient == null;
    _apiClient = widget.apiClient ?? EventsApiClient();
    _loadDrafts();
  }

  @override
  void dispose() {
    if (_ownsClient) _apiClient.close();
    super.dispose();
  }

  Future<void> _loadDrafts() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final drafts = await _apiClient.getDraftEvents();
      if (!mounted) return;
      setState(() {
        _drafts = drafts;
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

  Future<void> _publish(Event event) async {
    setState(() {
      _publishingIds.add(event.id);
      _publishErrors.remove(event.id);
    });

    try {
      await _apiClient.publishEvent(event.id);
      if (!mounted) return;
      setState(() {
        _publishingIds.remove(event.id);
        _drafts = _drafts?.where((e) => e.id != event.id).toList();
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('"${event.title}" published.')),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _publishingIds.remove(event.id);
        _publishErrors[event.id] = e.toString();
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
                  padding: const EdgeInsets.fromLTRB(8, 8, 20, 8),
                  child: Row(
                    children: [
                      IconButton(
                        icon: const Icon(Icons.arrow_back,
                            color: VilviaColors.charcoal),
                        tooltip: 'Back',
                        onPressed: () => Navigator.of(context).pop(),
                      ),
                      Text('Draft Events', style: textTheme.headlineMedium),
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
              'Failed to load draft events.',
              style: textTheme.bodyLarge?.copyWith(color: VilviaColors.gray),
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: _loadDrafts,
              child: const Text('Retry'),
            ),
          ],
        ),
      );
    }

    final drafts = _drafts ?? [];
    if (drafts.isEmpty) {
      return Center(
        child: Text(
          'No draft events.',
          style: textTheme.bodyLarge?.copyWith(color: VilviaColors.gray),
        ),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
      itemCount: drafts.length,
      separatorBuilder: (_, _) => const SizedBox(height: 12),
      itemBuilder: (context, index) =>
          _buildDraftTile(drafts[index], textTheme),
    );
  }

  Widget _buildDraftTile(Event event, TextTheme textTheme) {
    final isPublishing = _publishingIds.contains(event.id);
    final error = _publishErrors[event.id];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        EventCard(event: event),
        const SizedBox(height: 8),
        if (error != null) ...[
          Text(
            error,
            style: textTheme.bodySmall?.copyWith(color: VilviaColors.error),
          ),
          const SizedBox(height: 8),
        ],
        SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            onPressed: isPublishing ? null : () => _publish(event),
            child: isPublishing
                ? const SizedBox(
                    height: 18,
                    width: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: VilviaColors.surface,
                    ),
                  )
                : const Text('Publish'),
          ),
        ),
      ],
    );
  }
}
