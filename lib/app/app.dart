import 'package:flutter/material.dart';

class VilviaApp extends StatelessWidget {
  const VilviaApp({super.key});

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(
      title: 'Vilvia',
      home: Scaffold(
        body: Center(
          child: Text('Vilvia'),
        ),
      ),
    );
  }
}
