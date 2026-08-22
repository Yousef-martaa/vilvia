import 'package:flutter/material.dart';

import 'package:vilvia/features/auth/data/auth_service.dart';
import 'package:vilvia/features/home/presentation/widgets/explore_community_button.dart';
import 'package:vilvia/features/home/presentation/widgets/explore_events_button.dart';
import 'package:vilvia/features/home/presentation/widgets/explore_resources_button.dart';
import 'package:vilvia/features/home/presentation/widgets/home_header.dart';
import 'package:vilvia/features/home/presentation/widgets/hero_section.dart';

/// The Home screen (Issue #57, extended by Issue #63). Deliberately
/// minimal for the MVP: the approved logo, hero illustration and hero
/// copy, and one real, working entry point per implemented feature
/// (Resources, Events, Community). Earlier drafts also showed a search bar,
/// quick-action shortcuts, a fake "Upcoming" event card, an "Active
/// Circles" list, and a five-tab bottom navigation bar — all removed
/// because they had no backend behind them. Only entry points for
/// features that actually exist get added here.
class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key, this.authService});

  final AuthService? authService;

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
                HomeHeader(authService: authService),
                const SizedBox(height: 20),
                const HeroSection(),
                const SizedBox(height: 24),
                const ExploreResourcesButton(),
                const SizedBox(height: 12),
                const ExploreEventsButton(),
                const SizedBox(height: 12),
                const ExploreCommunityButton(),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
