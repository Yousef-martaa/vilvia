import 'package:flutter/material.dart';

import 'package:vilvia/features/home/presentation/screens/home_screen.dart';
import 'package:vilvia/theme/vilvia_theme.dart';

class VilviaApp extends StatelessWidget {
  const VilviaApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Vilvia',
      theme: VilviaTheme.light(),
      home: const HomeScreen(),
    );
  }
}
