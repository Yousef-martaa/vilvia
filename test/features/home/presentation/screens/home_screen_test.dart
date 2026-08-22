import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:vilvia/features/auth/data/auth_service.dart';
import 'package:vilvia/features/community/presentation/screens/community_screen.dart';
import 'package:vilvia/features/events/presentation/screens/events_screen.dart';
import 'package:vilvia/features/home/presentation/screens/home_screen.dart';
import 'package:vilvia/features/information/presentation/screens/resources_screen.dart';

// Home renders a sign-in-state affordance backed by AuthService, which by
// default reaches Supabase.instance -- never initialized in tests. A
// no-session fake avoids that without needing a real Supabase project.
class _FakeAuthService extends AuthService {
  @override
  Session? get currentSession => null;

  @override
  Stream<AuthState> get onAuthStateChange => const Stream.empty();
}

void main() {
  Widget wrap() => MaterialApp(home: HomeScreen(authService: _FakeAuthService()));

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

  testWidgets('tapping Explore Events navigates to EventsScreen',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(400, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(wrap());
    await tester.pump();

    await tester.tap(find.text('Explore Events'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.byType(EventsScreen), findsOneWidget);
  });

  testWidgets('tapping Explore Community navigates to CommunityScreen',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(400, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(wrap());
    await tester.pump();

    await tester.tap(find.text('Explore Community'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.byType(CommunityScreen), findsOneWidget);
  });
}
