import 'package:flutter/material.dart';

import 'package:vilvia/features/events/presentation/screens/events_screen.dart';

/// Home's second real, working entry point (Issue #63): a button into the
/// Events feature, added only because Events now genuinely exists. Styled
/// identically to [ExploreResourcesButton] for a clean, consistent Home
/// layout.
class ExploreEventsButton extends StatelessWidget {
  const ExploreEventsButton({super.key});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton.icon(
        onPressed: () => Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const EventsScreen()),
        ),
        icon: const Icon(Icons.event),
        label: const Text('Explore Events'),
      ),
    );
  }
}
