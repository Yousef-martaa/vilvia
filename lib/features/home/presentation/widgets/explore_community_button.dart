import 'package:flutter/material.dart';

import 'package:vilvia/features/community/presentation/screens/community_screen.dart';

class ExploreCommunityButton extends StatelessWidget {
  const ExploreCommunityButton({super.key});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton.icon(
        onPressed: () => Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const CommunityScreen()),
        ),
        icon: const Icon(Icons.forum_outlined),
        label: const Text('Explore Community'),
      ),
    );
  }
}
