import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:vilvia/app/app.dart';
import 'package:vilvia/features/auth/data/auth_service.dart';

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
  testWidgets('VilviaApp renders HomeScreen', (WidgetTester tester) async {
    await tester.pumpWidget(VilviaApp(authService: _FakeAuthService()));
    // Hero headline is always present, no async load involved.
    expect(
      find.text('“It takes a village to raise a child.”'),
      findsOneWidget,
    );
  });
}
