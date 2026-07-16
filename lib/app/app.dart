import 'package:flutter/material.dart';

import 'package:vilvia/features/information/presentation/screens/resources_screen.dart';

class VilviaApp extends StatelessWidget {
  const VilviaApp({super.key});

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(
      title: 'Vilvia',
      home: ResourcesScreen(),
    );
  }
}
