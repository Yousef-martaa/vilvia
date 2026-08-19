import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:vilvia/features/auth/data/auth_service.dart';
import 'package:vilvia/features/auth/data/profile.dart';
import 'package:vilvia/features/auth/data/profile_api_client.dart';
import 'package:vilvia/features/events/data/event.dart';
import 'package:vilvia/features/events/data/events_api_client.dart';
import 'package:vilvia/features/events/presentation/screens/create_event_screen.dart';
import 'package:vilvia/features/events/presentation/screens/events_screen.dart';

// --- Stub helpers ---

Event _fakeEvent({
  String title = 'Test Event',
  String location = 'Community Centre',
  String description = 'A short description',
  DateTime? startsAt,
}) {
  final start = startsAt ?? DateTime.now().toUtc().add(const Duration(days: 1));
  return Event(
    id: '1',
    title: title,
    description: description,
    location: location,
    startsAt: start,
    endsAt: start.add(const Duration(hours: 2)),
    createdAt: DateTime(2024),
    updatedAt: DateTime(2024),
  );
}

class _StubApiClient extends EventsApiClient {
  final Future<List<Event>> Function() _fn;

  _StubApiClient(this._fn) : super(baseUrl: 'http://test');

  @override
  Future<List<Event>> getEvents() => _fn();
}

class _SpyApiClient extends EventsApiClient {
  bool closeCalled = false;

  _SpyApiClient() : super(baseUrl: 'http://test');

  @override
  Future<List<Event>> getEvents() async => [];

  @override
  void close() => closeCalled = true;
}

User _fakeUser() => User(
      id: 'admin-1',
      appMetadata: const {},
      userMetadata: const {},
      aud: 'authenticated',
      createdAt: '2024-01-01T00:00:00Z',
      email: 'admin@example.com',
    );

Session _fakeSession() =>
    Session(accessToken: 'fake-token', tokenType: 'bearer', user: _fakeUser());

Profile _fakeProfile(UserRole role) => Profile(
      id: 'admin-1',
      firstName: 'Robin',
      email: 'admin@example.com',
      role: role,
      createdAt: DateTime(2024),
      updatedAt: DateTime(2024),
    );

/// A controllable fake: [currentSession] starts at [initialSession] and
/// can be changed via [signOut]/[signIn], which also emit on
/// [onAuthStateChange] the same way a real sign-in/out would -- this is
/// what lets a test simulate "admin signs out while this screen is open"
/// without touching Supabase.
class _FakeAuthService extends AuthService {
  _FakeAuthService({Session? initialSession}) : _session = initialSession;

  Session? _session;
  final _controller = StreamController<AuthState>.broadcast();

  @override
  Session? get currentSession => _session;

  @override
  Stream<AuthState> get onAuthStateChange => _controller.stream;

  void simulateSignOut() {
    _session = null;
    _controller.add(const AuthState(AuthChangeEvent.signedOut, null));
  }

  void disposeFake() => _controller.close();
}

class _FakeProfileApiClient extends ProfileApiClient {
  _FakeProfileApiClient({this.getMeResult, this.getMeError})
      : super(accessToken: () => null);

  final Profile? getMeResult;
  final Object? getMeError;

  @override
  Future<Profile> getMe() async {
    if (getMeError != null) throw getMeError!;
    return getMeResult!;
  }
}

// --- Tests ---

void main() {
  Widget wrap(EventsApiClient client) =>
      MaterialApp(home: EventsScreen(apiClient: client));

  testWidgets('shows loading indicator before response arrives',
      (tester) async {
    final client = _StubApiClient(() => Completer<List<Event>>().future);
    await tester.pumpWidget(wrap(client));

    expect(find.byType(CircularProgressIndicator), findsOneWidget);
  });

  testWidgets('shows event title, location, and description on success',
      (tester) async {
    final client = _StubApiClient(
      () async => [
        _fakeEvent(
          title: 'Toddler Storytime',
          location: 'Public Library',
          description: 'Weekly storytime for toddlers.',
        ),
      ],
    );
    await tester.pumpWidget(wrap(client));
    await tester.pumpAndSettle();

    expect(find.text('Toddler Storytime'), findsOneWidget);
    expect(find.text('Public Library'), findsOneWidget);
    expect(find.text('Weekly storytime for toddlers.'), findsOneWidget);
  });

  testWidgets('shows empty message when list is empty', (tester) async {
    final client = _StubApiClient(() async => []);
    await tester.pumpWidget(wrap(client));
    await tester.pumpAndSettle();

    expect(find.text('No upcoming events.'), findsOneWidget);
  });

  testWidgets('shows error message and retry button on failure',
      (tester) async {
    final client = _StubApiClient(() async => throw Exception('Network error'));
    await tester.pumpWidget(wrap(client));
    await tester.pumpAndSettle();

    expect(find.text('Failed to load events.'), findsOneWidget);
    expect(find.text('Retry'), findsOneWidget);
  });

  testWidgets('retry button reloads and shows events', (tester) async {
    var callCount = 0;
    final client = _StubApiClient(() {
      callCount++;
      if (callCount == 1) return Future.error(Exception('First call fails'));
      return Future.value([_fakeEvent(title: 'Loaded Event')]);
    });

    await tester.pumpWidget(wrap(client));
    await tester.pumpAndSettle();
    expect(find.text('Failed to load events.'), findsOneWidget);

    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();
    expect(find.text('Loaded Event'), findsOneWidget);
  });

  testWidgets('does not close an injected api client on dispose',
      (tester) async {
    final spy = _SpyApiClient();
    await tester.pumpWidget(wrap(spy));
    await tester.pumpAndSettle();

    await tester.pumpWidget(const SizedBox());
    expect(spy.closeCalled, isFalse);
  });

  testWidgets('closes internally created api client on dispose',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(home: EventsScreen()));
    await tester.pumpAndSettle();

    expect(() => tester.pumpWidget(const SizedBox()), returnsNormally);
  });

  // --- Admin-only "New Event" entry point (Issue #75) ---

  Widget wrapWithAdminDeps({
    required _FakeAuthService authService,
    required _FakeProfileApiClient profileApiClient,
    EventsApiClient? apiClient,
  }) {
    return MaterialApp(
      home: EventsScreen(
        apiClient: apiClient ?? _StubApiClient(() async => []),
        authService: authService,
        profileApiClient: profileApiClient,
      ),
    );
  }

  testWidgets('shows the New Event button when the caller is an admin',
      (tester) async {
    final authService = _FakeAuthService(initialSession: _fakeSession());
    final profileClient =
        _FakeProfileApiClient(getMeResult: _fakeProfile(UserRole.admin));

    await tester.pumpWidget(wrapWithAdminDeps(
      authService: authService,
      profileApiClient: profileClient,
    ));
    await tester.pumpAndSettle();

    expect(find.text('New Event'), findsOneWidget);
    authService.disposeFake();
  });

  testWidgets('does not show the New Event button for a parent',
      (tester) async {
    final authService = _FakeAuthService(initialSession: _fakeSession());
    final profileClient =
        _FakeProfileApiClient(getMeResult: _fakeProfile(UserRole.parent));

    await tester.pumpWidget(wrapWithAdminDeps(
      authService: authService,
      profileApiClient: profileClient,
    ));
    await tester.pumpAndSettle();

    expect(find.text('New Event'), findsNothing);
    authService.disposeFake();
  });

  testWidgets('does not show the New Event button when signed out',
      (tester) async {
    final authService = _FakeAuthService(initialSession: null);
    final profileClient =
        _FakeProfileApiClient(getMeResult: _fakeProfile(UserRole.admin));

    await tester.pumpWidget(wrapWithAdminDeps(
      authService: authService,
      profileApiClient: profileClient,
    ));
    await tester.pumpAndSettle();

    expect(find.text('New Event'), findsNothing);
    authService.disposeFake();
  });

  testWidgets(
      'does not show the New Event button when fetching the Profile fails '
      '(fails closed)', (tester) async {
    final authService = _FakeAuthService(initialSession: _fakeSession());
    final profileClient =
        _FakeProfileApiClient(getMeError: ProfileNotFoundException());

    await tester.pumpWidget(wrapWithAdminDeps(
      authService: authService,
      profileApiClient: profileClient,
    ));
    await tester.pumpAndSettle();

    expect(find.text('New Event'), findsNothing);
    authService.disposeFake();
  });

  testWidgets('hides the New Event button after an admin signs out',
      (tester) async {
    final authService = _FakeAuthService(initialSession: _fakeSession());
    final profileClient =
        _FakeProfileApiClient(getMeResult: _fakeProfile(UserRole.admin));

    await tester.pumpWidget(wrapWithAdminDeps(
      authService: authService,
      profileApiClient: profileClient,
    ));
    await tester.pumpAndSettle();
    expect(find.text('New Event'), findsOneWidget);

    authService.simulateSignOut();
    await tester.pumpAndSettle();

    expect(find.text('New Event'), findsNothing);
    authService.disposeFake();
  });

  testWidgets('tapping New Event navigates to CreateEventScreen',
      (tester) async {
    final authService = _FakeAuthService(initialSession: _fakeSession());
    final profileClient =
        _FakeProfileApiClient(getMeResult: _fakeProfile(UserRole.admin));

    await tester.pumpWidget(wrapWithAdminDeps(
      authService: authService,
      profileApiClient: profileClient,
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.text('New Event'));
    await tester.pumpAndSettle();

    expect(find.byType(CreateEventScreen), findsOneWidget);
    authService.disposeFake();
  });
}
