import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:vilvia/features/auth/data/auth_service.dart';
import 'package:vilvia/features/auth/data/profile.dart';
import 'package:vilvia/features/auth/data/profile_api_client.dart';
import 'package:vilvia/features/auth/presentation/screens/sign_up_screen.dart';

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
  _FakeAuthService({this.signUpResult, this.signUpError});

  final AuthResponse? signUpResult;
  final Object? signUpError;
  bool signUpCalled = false;

  @override
  Future<AuthResponse> signUp({
    required String email,
    required String password,
  }) async {
    signUpCalled = true;
    if (signUpError != null) throw signUpError!;
    return signUpResult!;
  }
}

class _FakeProfileApiClient extends ProfileApiClient {
  _FakeProfileApiClient() : super(accessToken: () => null);

  bool bootstrapCalled = false;
  String? bootstrapFirstName;
  Gender? bootstrapGender;

  @override
  Future<Profile> bootstrap({
    required String firstName,
    required Gender gender,
  }) async {
    bootstrapCalled = true;
    bootstrapFirstName = firstName;
    bootstrapGender = gender;
    return Profile(
      id: 'user-1',
      firstName: firstName,
      email: 'parent@example.com',
      role: 'parent',
      gender: gender,
      createdAt: DateTime(2024),
      updatedAt: DateTime(2024),
    );
  }
}

void main() {
  Widget wrap(AuthService authService, ProfileApiClient profileApiClient) {
    return MaterialApp(
      home: SignUpScreen(
        authService: authService,
        profileApiClient: profileApiClient,
      ),
    );
  }

  Future<void> fillForm(WidgetTester tester) async {
    await tester.enterText(
      find.widgetWithText(TextField, 'First name'),
      'Rowan',
    );
    await tester.enterText(
      find.widgetWithText(TextField, 'Email'),
      'rowan@example.com',
    );
    await tester.enterText(
      find.widgetWithText(TextField, 'Password'),
      'password123',
    );
    await tester.tap(find.text('Male'));
    await tester.pump();
  }

  testWidgets(
      'signing up with an immediate session bootstraps the profile with the entered name',
      (tester) async {
    final authService = _FakeAuthService(
      signUpResult: AuthResponse(session: _fakeSession()),
    );
    final profileClient = _FakeProfileApiClient();

    await tester.pumpWidget(wrap(authService, profileClient));
    await fillForm(tester);
    await tester.tap(find.text('Sign Up'));
    await tester.pumpAndSettle();

    expect(profileClient.bootstrapCalled, isTrue);
    expect(profileClient.bootstrapFirstName, 'Rowan');
    expect(profileClient.bootstrapGender, Gender.male);
  });

  testWidgets(
      'submitting with an empty first name shows a validation error and does not sign up',
      (tester) async {
    final authService = _FakeAuthService(
      signUpResult: AuthResponse(session: _fakeSession()),
    );
    final profileClient = _FakeProfileApiClient();

    await tester.pumpWidget(wrap(authService, profileClient));
    await tester.enterText(
      find.widgetWithText(TextField, 'Email'),
      'rowan@example.com',
    );
    await tester.enterText(
      find.widgetWithText(TextField, 'Password'),
      'password123',
    );
    await tester.tap(find.text('Male'));
    await tester.pump();
    await tester.tap(find.text('Sign Up'));
    await tester.pumpAndSettle();

    expect(find.textContaining('Please enter a first name'), findsOneWidget);
    expect(authService.signUpCalled, isFalse);
    expect(profileClient.bootstrapCalled, isFalse);
  });

  testWidgets(
      'submitting with a first name over 200 characters shows a validation error and does not sign up',
      (tester) async {
    final authService = _FakeAuthService(
      signUpResult: AuthResponse(session: _fakeSession()),
    );
    final profileClient = _FakeProfileApiClient();

    await tester.pumpWidget(wrap(authService, profileClient));
    await tester.enterText(
      find.widgetWithText(TextField, 'First name'),
      'A' * 201,
    );
    await tester.enterText(
      find.widgetWithText(TextField, 'Email'),
      'rowan@example.com',
    );
    await tester.enterText(
      find.widgetWithText(TextField, 'Password'),
      'password123',
    );
    await tester.tap(find.text('Male'));
    await tester.pump();
    await tester.tap(find.text('Sign Up'));
    await tester.pumpAndSettle();

    expect(find.textContaining('Please enter a first name'), findsOneWidget);
    expect(authService.signUpCalled, isFalse);
    expect(profileClient.bootstrapCalled, isFalse);
  });

  testWidgets(
      'submitting without selecting a gender shows an error and does not sign up',
      (tester) async {
    final authService = _FakeAuthService(
      signUpResult: AuthResponse(session: _fakeSession()),
    );
    final profileClient = _FakeProfileApiClient();

    await tester.pumpWidget(wrap(authService, profileClient));
    await tester.enterText(
      find.widgetWithText(TextField, 'First name'),
      'Rowan',
    );
    await tester.enterText(
      find.widgetWithText(TextField, 'Email'),
      'rowan@example.com',
    );
    await tester.enterText(
      find.widgetWithText(TextField, 'Password'),
      'password123',
    );
    await tester.tap(find.text('Sign Up'));
    await tester.pumpAndSettle();

    expect(find.textContaining('Please select a gender'), findsOneWidget);
    expect(profileClient.bootstrapCalled, isFalse);
  });

  testWidgets(
      'signing up with no session (email confirmation pending) shows a check-your-email state and does not bootstrap',
      (tester) async {
    final authService = _FakeAuthService(
      signUpResult: AuthResponse(user: _fakeUser()),
    );
    final profileClient = _FakeProfileApiClient();

    await tester.pumpWidget(wrap(authService, profileClient));
    await fillForm(tester);
    await tester.tap(find.text('Sign Up'));
    await tester.pumpAndSettle();

    expect(find.textContaining('Check your email'), findsOneWidget);
    expect(profileClient.bootstrapCalled, isFalse);
  });

  testWidgets('shows an error message when sign up fails', (tester) async {
    final authService = _FakeAuthService(
      signUpError: Exception('Email already registered'),
    );
    final profileClient = _FakeProfileApiClient();

    await tester.pumpWidget(wrap(authService, profileClient));
    await fillForm(tester);
    await tester.tap(find.text('Sign Up'));
    await tester.pumpAndSettle();

    expect(find.textContaining('Email already registered'), findsOneWidget);
    expect(profileClient.bootstrapCalled, isFalse);
  });
}
