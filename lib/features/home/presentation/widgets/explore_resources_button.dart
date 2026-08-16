import 'package:flutter/material.dart';

import 'package:vilvia/features/information/presentation/screens/resources_screen.dart';

/// Home's one real, working entry point: a primary button into the
/// existing Resources feature. Styled with the shared Vilvia primary
/// button theme (see [VilviaTheme]).
class ExploreResourcesButton extends StatelessWidget {
  const ExploreResourcesButton({super.key});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton.icon(
        onPressed: () => Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const ResourcesScreen()),
        ),
        icon: const Icon(Icons.menu_book),
        label: const Text('Explore Resources'),
      ),
    );
  }
}
