import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:vilvia/features/auth/data/auth_service.dart';
import 'package:vilvia/features/auth/data/profile.dart';
import 'package:vilvia/features/auth/data/profile_api_client.dart';
import 'package:vilvia/features/auth/presentation/screens/sign_in_screen.dart';

User _fakeUser({
  String email = 'parent@example.com',
  Map<String, dynamic>? metadata,
}) =>
    User(
      id: 'user-1',
      appMetadata: const {},
      userMetadata: metadata ?? const {},
      aud: 'authenticated',
      createdAt: '2024-01-01T00:00:00Z',
      email: email,
    );

Session _fakeSession({
  String email = 'parent@example.com',
  Map<String, dynamic>? metadata,
}) =>
    Session(
      accessToken: 'fake-access-token',
      tokenType: 'bearer',
      user: _fakeUser(email: email, metadata: metadata),
    );

Profile _fakeProfile({
  String firstName = 'Rowan',
  String lastName = 'Smith',
  ParentRole? parentRole,
}) =>
    Profile(
      id: 'user-1',
      firstName: firstName,
      lastName: lastName,
      email: 'parent@example.com',
      role: UserRole.parent,
      parentRole: parentRole,
      createdAt: DateTime(2024),
      updatedAt: DateTime(2024),
    );

class _FakeAuthService extends AuthService {
  _FakeAuthService({this.signInResult, this.signInError});

  final AuthResponse? signInResult;
  final Object? signInError;

  @override
  Session? get currentSession => signInResult?.session;

  @override
  Future<AuthResponse> signInWithPassword({
    required String email,
    required String password,
  }) async {
    if (signInError != null) throw signInError!;
    return signInResult!;
  }
}

class _FakeProfileApiClient extends ProfileApiClient {
  _FakeProfileApiClient({
    this.getMeResult,
    this.getMeError,
    this.bootstrapError,
  }) : super(accessToken: () => null);

  final Profile? getMeResult;
  final Object? getMeError;
  final Object? bootstrapError;
  bool bootstrapCalled = false;
  String? bootstrapFirstName;
  String? bootstrapLastName;
  ParentRole? bootstrapParentRole;

  @override
  Future<Profile> getMe() async {
    if (getMeError != null) throw getMeError!;
    return getMeResult!;
  }

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
    if (bootstrapError != null) throw bootstrapError!;
    return _fakeProfile(
      firstName: firstName,
      lastName: lastName,
      parentRole: parentRole,
    );
  }
}

void main() {
  Widget wrap(AuthService authService, ProfileApiClient profileApiClient) {
    return MaterialApp(
      home: SignInScreen(
        authService: authService,
        profileApiClient: profileApiClient,
      ),
    );
  }

  Future<void> fillForm(WidgetTester tester) async {
    await tester.enterText(
      find.widgetWithText(TextField, 'Email'),
      'rowan@example.com',
    );
    await tester.enterText(
      find.widgetWithText(TextField, 'Password'),
      'password123',
    );
  }

  testWidgets('signing in with an existing profile does not need setup',
      (tester) async {
    final authService = _FakeAuthService(
      signInResult: AuthResponse(session: _fakeSession()),
    );
    final profileClient = _FakeProfileApiClient(getMeResult: _fakeProfile());

    await tester.pumpWidget(wrap(authService, profileClient));
    await fillForm(tester);
    await tester.ensureVisible(find.text('Sign In'));
    await tester.tap(find.text('Sign In'));
    await tester.pumpAndSettle();

    expect(find.text('Finish setting up'), findsNothing);
    expect(profileClient.bootstrapCalled, isFalse);
  });

  testWidgets(
      'signing in with no profile but with signup metadata auto-bootstraps',
      (tester) async {
    final authService = _FakeAuthService(
      signInResult: AuthResponse(
        session: _fakeSession(metadata: {
          'first_name': 'Rowan',
          'last_name': 'Smith',
          'parent_role': 'mother',
        }),
      ),
    );
    final profileClient = _FakeProfileApiClient(
      getMeError: ProfileNotFoundException(),
    );

    await tester.pumpWidget(wrap(authService, profileClient));
    await fillForm(tester);
    await tester.ensureVisible(find.text('Sign In'));
    await tester.tap(find.text('Sign In'));
    await tester.pumpAndSettle();

    expect(find.text('Finish setting up'), findsNothing);
    expect(profileClient.bootstrapCalled, isTrue);
    expect(profileClient.bootstrapFirstName, 'Rowan');
    expect(profileClient.bootstrapLastName, 'Smith');
    expect(profileClient.bootstrapParentRole, ParentRole.mother);
  });

  testWidgets(
      'signing in with metadata missing parent_role still auto-bootstraps with null role',
      (tester) async {
    final authService = _FakeAuthService(
      signInResult: AuthResponse(
        session: _fakeSession(metadata: {
          'first_name': 'Rowan',
          'last_name': 'Smith',
        }),
      ),
    );
    final profileClient = _FakeProfileApiClient(
      getMeError: ProfileNotFoundException(),
    );

    await tester.pumpWidget(wrap(authService, profileClient));
    await fillForm(tester);
    await tester.ensureVisible(find.text('Sign In'));
    await tester.tap(find.text('Sign In'));
    await tester.pumpAndSettle();

    expect(find.text('Finish setting up'), findsNothing);
    expect(profileClient.bootstrapCalled, isTrue);
    expect(profileClient.bootstrapFirstName, 'Rowan');
    expect(profileClient.bootstrapLastName, 'Smith');
    expect(profileClient.bootstrapParentRole, isNull);
  });

  testWidgets(
      'auto-bootstrap failure shows user-friendly error and prefills form for retry',
      (tester) async {
    final authService = _FakeAuthService(
      signInResult: AuthResponse(
        session: _fakeSession(metadata: {
          'first_name': 'Rowan',
          'last_name': 'Smith',
          'parent_role': 'mother',
        }),
      ),
    );
    final profileClient = _FakeProfileApiClient(
      getMeError: ProfileNotFoundException(),
      bootstrapError: Exception('Server timeout'),
    );

    await tester.pumpWidget(wrap(authService, profileClient));
    await fillForm(tester);
    await tester.ensureVisible(find.text('Sign In'));
    await tester.tap(find.text('Sign In'));
    await tester.pumpAndSettle();

    expect(find.text('Finish setting up'), findsOneWidget);
    expect(
      find.text('Could not finish setting up your account. Please try again.'),
      findsOneWidget,
    );
    expect(find.widgetWithText(TextField, 'Rowan'), findsOneWidget);
    expect(find.widgetWithText(TextField, 'Smith'), findsOneWidget);
  });

  testWidgets(
      'signing in with incomplete metadata prefills available fields in finish-setup',
      (tester) async {
    final authService = _FakeAuthService(
      signInResult: AuthResponse(
        session: _fakeSession(metadata: {
          'first_name': 'Rowan',
        }),
      ),
    );
    final profileClient = _FakeProfileApiClient(
      getMeError: ProfileNotFoundException(),
    );

    await tester.pumpWidget(wrap(authService, profileClient));
    await fillForm(tester);
    await tester.ensureVisible(find.text('Sign In'));
    await tester.tap(find.text('Sign In'));
    await tester.pumpAndSettle();

    expect(find.text('Finish setting up'), findsOneWidget);
    expect(find.widgetWithText(TextField, 'Rowan'), findsOneWidget);
    expect(profileClient.bootstrapCalled, isFalse);
  });

  testWidgets(
      'signing in with no profile and no metadata shows manual finish-setup step',
      (tester) async {
    final authService = _FakeAuthService(
      signInResult: AuthResponse(session: _fakeSession()),
    );
    final profileClient = _FakeProfileApiClient(
      getMeError: ProfileNotFoundException(),
    );

    await tester.pumpWidget(wrap(authService, profileClient));
    await fillForm(tester);
    await tester.ensureVisible(find.text('Sign In'));
    await tester.tap(find.text('Sign In'));
    await tester.pumpAndSettle();

    expect(find.text('Finish setting up'), findsOneWidget);

    await tester.enterText(
      find.widgetWithText(TextField, 'First name'),
      'Rowan',
    );
    await tester.enterText(
      find.widgetWithText(TextField, 'Last name'),
      'Smith',
    );
    await tester.ensureVisible(find.text('Mother'));
    await tester.tap(find.text('Mother'));
    await tester.pump();
    await tester.ensureVisible(find.text('Complete Setup'));
    await tester.tap(find.text('Complete Setup'));
    await tester.pumpAndSettle();

    expect(profileClient.bootstrapCalled, isTrue);
    expect(profileClient.bootstrapFirstName, 'Rowan');
    expect(profileClient.bootstrapLastName, 'Smith');
    expect(profileClient.bootstrapParentRole, ParentRole.mother);
  });

  testWidgets(
      'completing setup with an empty first name shows a validation error and does not bootstrap',
      (tester) async {
    final authService = _FakeAuthService(
      signInResult: AuthResponse(session: _fakeSession()),
    );
    final profileClient = _FakeProfileApiClient(
      getMeError: ProfileNotFoundException(),
    );

    await tester.pumpWidget(wrap(authService, profileClient));
    await fillForm(tester);
    await tester.ensureVisible(find.text('Sign In'));
    await tester.tap(find.text('Sign In'));
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.text('Mother'));
    await tester.tap(find.text('Mother'));
    await tester.pump();
    await tester.ensureVisible(find.text('Complete Setup'));
    await tester.tap(find.text('Complete Setup'));
    await tester.pumpAndSettle();

    expect(find.textContaining('Please enter a first name'), findsOneWidget);
    expect(profileClient.bootstrapCalled, isFalse);
  });

  testWidgets(
      'completing setup with a first name over 200 characters shows a validation error and does not bootstrap',
      (tester) async {
    final authService = _FakeAuthService(
      signInResult: AuthResponse(session: _fakeSession()),
    );
    final profileClient = _FakeProfileApiClient(
      getMeError: ProfileNotFoundException(),
    );

    await tester.pumpWidget(wrap(authService, profileClient));
    await fillForm(tester);
    await tester.ensureVisible(find.text('Sign In'));
    await tester.tap(find.text('Sign In'));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.widgetWithText(TextField, 'First name'),
      'A' * 201,
    );
    await tester.ensureVisible(find.text('Mother'));
    await tester.tap(find.text('Mother'));
    await tester.pump();
    await tester.ensureVisible(find.text('Complete Setup'));
    await tester.tap(find.text('Complete Setup'));
    await tester.pumpAndSettle();

    expect(find.textContaining('Please enter a first name'), findsOneWidget);
    expect(profileClient.bootstrapCalled, isFalse);
  });

  testWidgets(
      'completing setup without selecting a role succeeds with null role',
      (tester) async {
    final authService = _FakeAuthService(
      signInResult: AuthResponse(session: _fakeSession()),
    );
    final profileClient = _FakeProfileApiClient(
      getMeError: ProfileNotFoundException(),
    );

    await tester.pumpWidget(wrap(authService, profileClient));
    await fillForm(tester);
    await tester.ensureVisible(find.text('Sign In'));
    await tester.tap(find.text('Sign In'));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.widgetWithText(TextField, 'First name'),
      'Rowan',
    );
    await tester.enterText(
      find.widgetWithText(TextField, 'Last name'),
      'Smith',
    );
    await tester.ensureVisible(find.text('Complete Setup'));
    await tester.tap(find.text('Complete Setup'));
    await tester.pumpAndSettle();

    expect(profileClient.bootstrapCalled, isTrue);
    expect(profileClient.bootstrapFirstName, 'Rowan');
    expect(profileClient.bootstrapLastName, 'Smith');
    expect(profileClient.bootstrapParentRole, isNull);
  });

  testWidgets(
      'completing setup with empty last name shows an error and does not bootstrap',
      (tester) async {
    final authService = _FakeAuthService(
      signInResult: AuthResponse(session: _fakeSession()),
    );
    final profileClient = _FakeProfileApiClient(
      getMeError: ProfileNotFoundException(),
    );

    await tester.pumpWidget(wrap(authService, profileClient));
    await fillForm(tester);
    await tester.ensureVisible(find.text('Sign In'));
    await tester.tap(find.text('Sign In'));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.widgetWithText(TextField, 'First name'),
      'Rowan',
    );
    await tester.ensureVisible(find.text('Complete Setup'));
    await tester.tap(find.text('Complete Setup'));
    await tester.pumpAndSettle();

    expect(find.textContaining('Please enter a last name'), findsOneWidget);
    expect(profileClient.bootstrapCalled, isFalse);
  });

  testWidgets('shows user-friendly error message on AuthException',
      (tester) async {
    final authService = _FakeAuthService(
      signInError: const AuthException('Invalid login credentials'),
    );
    final profileClient = _FakeProfileApiClient();

    await tester.pumpWidget(wrap(authService, profileClient));
    await fillForm(tester);
    await tester.ensureVisible(find.text('Sign In'));
    await tester.tap(find.text('Sign In'));
    await tester.pumpAndSettle();

    expect(find.text('Invalid login credentials'), findsOneWidget);
  });

  testWidgets(
      'shows safe fallback error message on unknown error without leaking details',
      (tester) async {
    final authService = _FakeAuthService(
      signInError: Exception('SocketException: OS error 111'),
    );
    final profileClient = _FakeProfileApiClient();

    await tester.pumpWidget(wrap(authService, profileClient));
    await fillForm(tester);
    await tester.ensureVisible(find.text('Sign In'));
    await tester.tap(find.text('Sign In'));
    await tester.pumpAndSettle();

    expect(find.text('Could not sign in. Please try again.'), findsOneWidget);
    expect(find.textContaining('SocketException'), findsNothing);
  });
}
