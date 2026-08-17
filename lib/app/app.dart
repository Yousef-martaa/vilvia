import 'package:flutter/material.dart';

import 'package:vilvia/features/auth/data/auth_service.dart';
import 'package:vilvia/features/home/presentation/screens/home_screen.dart';
import 'package:vilvia/theme/vilvia_theme.dart';

class VilviaApp extends StatelessWidget {
  const VilviaApp({super.key, this.authService});

  /// Overridable for tests, which run without a real Supabase project.
  final AuthService? authService;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Vilvia',
      theme: VilviaTheme.light(),
      home: HomeScreen(authService: authService),
    );
  }
}
