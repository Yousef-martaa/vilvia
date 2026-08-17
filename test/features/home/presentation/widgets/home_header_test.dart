import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:vilvia/features/auth/data/auth_service.dart';
import 'package:vilvia/features/home/presentation/widgets/home_header.dart';

User _fakeUser({String email = 'parent@example.com'}) => User(
      id: 'user-1',
      appMetadata: const {},
      userMetadata: const {},
      aud: 'authenticated',
      createdAt: '2024-01-01T00:00:00Z',
      email: email,
    );

Session _fakeSession({String email = 'parent@example.com'}) => Session(
      accessToken: 'fake-access-token',
      tokenType: 'bearer',
      user: _fakeUser(email: email),
    );

class _FakeAuthService extends AuthService {
  _FakeAuthService({Session? initialSession}) : currentSession = initialSession;

  @override
  Session? currentSession;

  final _controller = StreamController<AuthState>.broadcast();
  bool signOutCalled = false;

  @override
  Stream<AuthState> get onAuthStateChange => _controller.stream;

  @override
  Future<void> signOut() async {
    signOutCalled = true;
    currentSession = null;
    _controller.add(const AuthState(AuthChangeEvent.signedOut, null));
  }

  void dispose() => _controller.close();
}

void main() {
  Widget wrap(AuthService authService) {
    return MaterialApp(
      home: Scaffold(body: HomeHeader(authService: authService)),
    );
  }

  testWidgets('shows Sign In when signed out', (tester) async {
    final authService = _FakeAuthService();
    await tester.pumpWidget(wrap(authService));
    await tester.pump();

    expect(find.text('Sign In'), findsOneWidget);
  });

  testWidgets('shows the account email and a sign-out control when signed in',
      (tester) async {
    final authService =
        _FakeAuthService(initialSession: _fakeSession(email: 'rowan@example.com'));
    await tester.pumpWidget(wrap(authService));
    await tester.pump();

    expect(find.text('rowan@example.com'), findsOneWidget);
    expect(find.byTooltip('Sign out'), findsOneWidget);
    expect(find.text('Sign In'), findsNothing);
  });

  testWidgets('tapping sign out calls AuthService.signOut', (tester) async {
    final authService =
        _FakeAuthService(initialSession: _fakeSession(email: 'rowan@example.com'));
    await tester.pumpWidget(wrap(authService));
    await tester.pump();

    await tester.tap(find.byTooltip('Sign out'));
    await tester.pump();

    expect(authService.signOutCalled, isTrue);
    expect(find.text('Sign In'), findsOneWidget);
  });
}
