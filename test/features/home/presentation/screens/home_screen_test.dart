import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:vilvia/features/home/presentation/screens/home_screen.dart';
import 'package:vilvia/features/information/presentation/screens/resources_screen.dart';

void main() {
  Widget wrap() => const MaterialApp(home: HomeScreen());

  testWidgets('shows the hero headline', (tester) async {
    await tester.pumpWidget(wrap());
    await tester.pump();

    expect(
      find.text('“It takes a village to raise a child.”'),
      findsOneWidget,
    );
  });

  testWidgets('tapping Explore Resources navigates to ResourcesScreen',
      (tester) async {
    // The Home body scrolls; use a tall surface so the button is laid out
    // without needing to simulate scrolling.
    await tester.binding.setSurfaceSize(const Size(400, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(wrap());
    await tester.pump();

    await tester.tap(find.text('Explore Resources'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.byType(ResourcesScreen), findsOneWidget);
  });
}
