import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'package:vilvia/features/events/data/event.dart';
import 'package:vilvia/theme/vilvia_colors.dart';
import 'package:vilvia/widgets/tinted_icon_badge.dart';

/// A single upcoming event row: date/time, title, location, and a short
/// description. Styled consistently with [ResourceCard] (tinted icon,
/// title, supporting text on a shadowed surface card), but not tappable --
/// there is no Event Details screen yet.
class EventCard extends StatelessWidget {
  const EventCard({super.key, required this.event});

  final Event event;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return Container(
      decoration: BoxDecoration(
        color: VilviaColors.surface,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: VilviaColors.charcoal.withValues(alpha: 0.06),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      padding: const EdgeInsets.all(16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const TintedIconBadge(
            icon: Icons.event,
            color: VilviaColors.terracotta,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  formatEventTimeRange(event.startsAt, event.endsAt),
                  style: textTheme.labelSmall?.copyWith(
                    color: VilviaColors.sageGreen,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 4),
                Text(event.title, style: textTheme.titleLarge),
                const SizedBox(height: 4),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(Icons.location_on_outlined,
                        size: 14, color: VilviaColors.gray),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        event.location,
                        style: textTheme.bodyMedium
                            ?.copyWith(color: VilviaColors.gray),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  event.description,
                  style: textTheme.bodyMedium
                      ?.copyWith(color: VilviaColors.gray),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Formats an event's start (and optional end) time in the viewer's local
/// timezone -- both [start] and [end] are UTC-normalized instants parsed
/// from the API's timezone-aware timestamps, so `.toLocal()` here is what
/// makes the displayed time correct for whoever is looking at it, rather
/// than a raw server-side value.
String formatEventTimeRange(DateTime start, DateTime? end) {
  final localStart = start.toLocal();
  final datePart = DateFormat('EEE, MMM d').format(localStart);
  final startTime = DateFormat('h:mm a').format(localStart);

  if (end == null) {
    return '$datePart · $startTime';
  }

  final localEnd = end.toLocal();
  final sameDay = localStart.year == localEnd.year &&
      localStart.month == localEnd.month &&
      localStart.day == localEnd.day;
  final endTime = DateFormat('h:mm a').format(localEnd);

  if (!sameDay) {
    return '$datePart · $startTime';
  }

  return '$datePart · $startTime–$endTime';
}
