import 'package:flutter/material.dart';

import 'package:vilvia/features/home/presentation/widgets/explore_resources_button.dart';
import 'package:vilvia/features/home/presentation/widgets/home_header.dart';
import 'package:vilvia/features/home/presentation/widgets/hero_section.dart';

/// The Home screen (Issue #57). Deliberately minimal for the MVP: the
/// approved logo, hero illustration and hero copy, and one real, working
/// entry point into the existing Resources feature. Earlier drafts also
/// showed a search bar, quick-action shortcuts, an "Upcoming" event card,
/// an "Active Circles" list, and a five-tab bottom navigation bar — all
/// removed because they had no backend behind them and only Resources is
/// implemented. See the PR description for the full rationale.
class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
              children: [
                const HomeHeader(),
                const SizedBox(height: 20),
                const HeroSection(),
                const SizedBox(height: 24),
                const ExploreResourcesButton(),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
