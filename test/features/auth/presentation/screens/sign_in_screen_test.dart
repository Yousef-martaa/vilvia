import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:vilvia/features/auth/data/auth_service.dart';
import 'package:vilvia/features/auth/data/profile.dart';
import 'package:vilvia/features/auth/data/profile_api_client.dart';
import 'package:vilvia/features/auth/presentation/screens/sign_in_screen.dart';

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

Profile _fakeProfile({String firstName = 'Rowan', Gender? gender}) => Profile(
      id: 'user-1',
      firstName: firstName,
      email: 'parent@example.com',
      role: UserRole.parent,
      gender: gender,
      createdAt: DateTime(2024),
      updatedAt: DateTime(2024),
    );

class _FakeAuthService extends AuthService {
  _FakeAuthService({this.signInResult, this.signInError});

  final AuthResponse? signInResult;
  final Object? signInError;

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
  _FakeProfileApiClient({this.getMeResult, this.getMeError})
      : super(accessToken: () => null);

  final Profile? getMeResult;
  final Object? getMeError;
  bool bootstrapCalled = false;
  String? bootstrapFirstName;
  Gender? bootstrapGender;

  @override
  Future<Profile> getMe() async {
    if (getMeError != null) throw getMeError!;
    return getMeResult!;
  }

  @override
  Future<Profile> bootstrap({
    required String firstName,
    required Gender gender,
  }) async {
    bootstrapCalled = true;
    bootstrapFirstName = firstName;
    bootstrapGender = gender;
    return _fakeProfile(firstName: firstName, gender: gender);
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
    await tester.tap(find.text('Sign In'));
    await tester.pumpAndSettle();

    expect(find.text('Finish setting up'), findsNothing);
    expect(profileClient.bootstrapCalled, isFalse);
  });

  testWidgets(
      'signing in with no profile yet shows an inline finish-setup step, and completing it bootstraps',
      (tester) async {
    final authService = _FakeAuthService(
      signInResult: AuthResponse(session: _fakeSession()),
    );
    final profileClient = _FakeProfileApiClient(
      getMeError: ProfileNotFoundException(),
    );

    await tester.pumpWidget(wrap(authService, profileClient));
    await fillForm(tester);
    await tester.tap(find.text('Sign In'));
    await tester.pumpAndSettle();

    expect(find.text('Finish setting up'), findsOneWidget);

    await tester.enterText(
      find.widgetWithText(TextField, 'First name'),
      'Rowan',
    );
    await tester.tap(find.text('Female'));
    await tester.pump();
    await tester.tap(find.text('Complete Setup'));
    await tester.pumpAndSettle();

    expect(profileClient.bootstrapCalled, isTrue);
    expect(profileClient.bootstrapFirstName, 'Rowan');
    expect(profileClient.bootstrapGender, Gender.female);
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
    await tester.tap(find.text('Sign In'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Female'));
    await tester.pump();
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
    await tester.tap(find.text('Sign In'));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.widgetWithText(TextField, 'First name'),
      'A' * 201,
    );
    await tester.tap(find.text('Female'));
    await tester.pump();
    await tester.tap(find.text('Complete Setup'));
    await tester.pumpAndSettle();

    expect(find.textContaining('Please enter a first name'), findsOneWidget);
    expect(profileClient.bootstrapCalled, isFalse);
  });

  testWidgets(
      'completing setup without selecting a gender shows an error and does not bootstrap',
      (tester) async {
    final authService = _FakeAuthService(
      signInResult: AuthResponse(session: _fakeSession()),
    );
    final profileClient = _FakeProfileApiClient(
      getMeError: ProfileNotFoundException(),
    );

    await tester.pumpWidget(wrap(authService, profileClient));
    await fillForm(tester);
    await tester.tap(find.text('Sign In'));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.widgetWithText(TextField, 'First name'),
      'Rowan',
    );
    await tester.tap(find.text('Complete Setup'));
    await tester.pumpAndSettle();

    expect(find.textContaining('Please select a gender'), findsOneWidget);
    expect(profileClient.bootstrapCalled, isFalse);
  });

  testWidgets('shows an error message when sign in fails', (tester) async {
    final authService = _FakeAuthService(
      signInError: Exception('Invalid credentials'),
    );
    final profileClient = _FakeProfileApiClient();

    await tester.pumpWidget(wrap(authService, profileClient));
    await fillForm(tester);
    await tester.tap(find.text('Sign In'));
    await tester.pumpAndSettle();

    expect(find.textContaining('Invalid credentials'), findsOneWidget);
  });
}
