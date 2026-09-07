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
  Map<String, dynamic>? lastUserMetadata;

  @override
  Session? get currentSession => signUpResult?.session;

  @override
  Future<AuthResponse> signUp({
    required String email,
    required String password,
    Map<String, dynamic>? userMetadata,
  }) async {
    signUpCalled = true;
    lastUserMetadata = userMetadata;
    if (signUpError != null) throw signUpError!;
    return signUpResult!;
  }
}

class _FakeProfileApiClient extends ProfileApiClient {
  _FakeProfileApiClient() : super(accessToken: () => null);

  bool bootstrapCalled = false;
  String? bootstrapFirstName;
  String? bootstrapLastName;
  ParentRole? bootstrapParentRole;

  @override
  Future<Profile> bootstrap({
    required String firstName,
    required String lastName,
    ParentRole? parentRole,
  }) async {
    bootstrapCalled = true;
    bootstrapFirstName = firstName;
    bootstrapLastName = lastName;
    bootstrapParentRole = parentRole;
    return Profile(
      id: 'user-1',
      firstName: firstName,
      lastName: lastName,
      email: 'parent@example.com',
      role: UserRole.parent,
      parentRole: parentRole,
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
      find.widgetWithText(TextField, 'Last name'),
      'Smith',
    );
    await tester.enterText(
      find.widgetWithText(TextField, 'Email'),
      'rowan@example.com',
    );
    await tester.enterText(
      find.widgetWithText(TextField, 'Password'),
      'password123',
    );
    await tester.enterText(
      find.widgetWithText(TextField, 'Confirm Password'),
      'password123',
    );
    await tester.tap(find.text('Mother'));
    await tester.pump();
  }

  testWidgets(
      'signing up with an immediate session bootstraps the profile with the entered info',
      (tester) async {
    final authService = _FakeAuthService(
      signUpResult: AuthResponse(session: _fakeSession()),
    );
    final profileClient = _FakeProfileApiClient();

    await tester.pumpWidget(wrap(authService, profileClient));
    await fillForm(tester);
    await tester.ensureVisible(find.text('Sign Up'));
    await tester.tap(find.text('Sign Up'));
    await tester.pumpAndSettle();

    expect(profileClient.bootstrapCalled, isTrue);
    expect(profileClient.bootstrapFirstName, 'Rowan');
    expect(profileClient.bootstrapLastName, 'Smith');
    expect(profileClient.bootstrapParentRole, ParentRole.mother);
  });

  testWidgets('signing up stores profile info in user_metadata', (tester) async {
    final authService = _FakeAuthService(
      signUpResult: AuthResponse(user: _fakeUser()),
    );
    final profileClient = _FakeProfileApiClient();

    await tester.pumpWidget(wrap(authService, profileClient));
    await fillForm(tester);
    await tester.ensureVisible(find.text('Sign Up'));
    await tester.tap(find.text('Sign Up'));
    await tester.pumpAndSettle();

    expect(authService.signUpCalled, isTrue);
    expect(authService.lastUserMetadata, {
      'first_name': 'Rowan',
      'last_name': 'Smith',
      'parent_role': 'mother',
    });
  });

  testWidgets('submitting with password mismatch shows an error', (tester) async {
    final authService = _FakeAuthService();
    final profileClient = _FakeProfileApiClient();

    await tester.pumpWidget(wrap(authService, profileClient));
    await fillForm(tester);
    await tester.enterText(
      find.widgetWithText(TextField, 'Confirm Password'),
      'mismatch',
    );
    await tester.ensureVisible(find.text('Sign Up'));
    await tester.tap(find.text('Sign Up'));
    await tester.pumpAndSettle();

    expect(find.textContaining('Passwords do not match'), findsOneWidget);
    expect(authService.signUpCalled, isFalse);
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
      find.widgetWithText(TextField, 'Last name'),
      'Smith',
    );
    await tester.enterText(
      find.widgetWithText(TextField, 'Email'),
      'rowan@example.com',
    );
    await tester.enterText(
      find.widgetWithText(TextField, 'Password'),
      'password123',
    );
    await tester.enterText(
      find.widgetWithText(TextField, 'Confirm Password'),
      'password123',
    );
    await tester.tap(find.text('Mother'));
    await tester.pump();
    await tester.ensureVisible(find.text('Sign Up'));
    await tester.tap(find.text('Sign Up'));
    await tester.pumpAndSettle();

    expect(find.textContaining('Please enter a first name'), findsOneWidget);
    expect(authService.signUpCalled, isFalse);
    expect(profileClient.bootstrapCalled, isFalse);
  });

  testWidgets(
      'submitting with an empty last name shows a validation error and does not sign up',
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
    await tester.enterText(
      find.widgetWithText(TextField, 'Confirm Password'),
      'password123',
    );
    await tester.tap(find.text('Mother'));
    await tester.pump();
    await tester.ensureVisible(find.text('Sign Up'));
    await tester.tap(find.text('Sign Up'));
    await tester.pumpAndSettle();

    expect(find.textContaining('Please enter a last name'), findsOneWidget);
    expect(authService.signUpCalled, isFalse);
    expect(profileClient.bootstrapCalled, isFalse);
  });

  testWidgets(
      'submitting with password under 6 characters shows an error and does not sign up',
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
      find.widgetWithText(TextField, 'Last name'),
      'Smith',
    );
    await tester.enterText(
      find.widgetWithText(TextField, 'Email'),
      'rowan@example.com',
    );
    await tester.enterText(
      find.widgetWithText(TextField, 'Password'),
      '12345',
    );
    await tester.enterText(
      find.widgetWithText(TextField, 'Confirm Password'),
      '12345',
    );
    await tester.ensureVisible(find.text('Sign Up'));
    await tester.tap(find.text('Sign Up'));
    await tester.pumpAndSettle();

    expect(
        find.textContaining('Password must be at least 6 characters'), findsOneWidget);
    expect(authService.signUpCalled, isFalse);
  });

  testWidgets(
      'submitting without selecting a role succeeds with null parent role',
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
      find.widgetWithText(TextField, 'Last name'),
      'Smith',
    );
    await tester.enterText(
      find.widgetWithText(TextField, 'Email'),
      'rowan@example.com',
    );
    await tester.enterText(
      find.widgetWithText(TextField, 'Password'),
      'password123',
    );
    await tester.enterText(
      find.widgetWithText(TextField, 'Confirm Password'),
      'password123',
    );
    await tester.ensureVisible(find.text('Sign Up'));
    await tester.tap(find.text('Sign Up'));
    await tester.pumpAndSettle();

    expect(profileClient.bootstrapCalled, isTrue);
    expect(profileClient.bootstrapFirstName, 'Rowan');
    expect(profileClient.bootstrapLastName, 'Smith');
    expect(profileClient.bootstrapParentRole, isNull);
    expect(authService.lastUserMetadata, {
      'first_name': 'Rowan',
      'last_name': 'Smith',
    });
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
    await tester.ensureVisible(find.text('Sign Up'));
    await tester.tap(find.text('Sign Up'));
    await tester.pumpAndSettle();

    expect(
      find.text(
        'If this email is new, we’ve sent a confirmation link. '
        'If you already have an account, please sign in instead.',
      ),
      findsOneWidget,
    );
    expect(profileClient.bootstrapCalled, isFalse);
  });

  testWidgets('shows user-friendly message on AuthException', (tester) async {
    final authService = _FakeAuthService(
      signUpError: const AuthException('User already registered'),
    );
    final profileClient = _FakeProfileApiClient();

    await tester.pumpWidget(wrap(authService, profileClient));
    await fillForm(tester);
    await tester.ensureVisible(find.text('Sign Up'));
    await tester.tap(find.text('Sign Up'));
    await tester.pumpAndSettle();

    expect(find.text('User already registered'), findsOneWidget);
    expect(profileClient.bootstrapCalled, isFalse);
  });

  testWidgets('shows safe fallback on unexpected error without leaking details',
      (tester) async {
    final authService = _FakeAuthService(
      signUpError: Exception('database connection closed at tcp://...'),
    );
    final profileClient = _FakeProfileApiClient();

    await tester.pumpWidget(wrap(authService, profileClient));
    await fillForm(tester);
    await tester.ensureVisible(find.text('Sign Up'));
    await tester.tap(find.text('Sign Up'));
    await tester.pumpAndSettle();

    expect(find.text('Could not create account. Please try again.'), findsOneWidget);
    expect(find.textContaining('tcp://'), findsNothing);
    expect(profileClient.bootstrapCalled, isFalse);
  });
}
