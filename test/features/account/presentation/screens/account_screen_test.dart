import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:vilvia/features/account/data/account_api_client.dart';
import 'package:vilvia/features/account/presentation/screens/account_screen.dart';
import 'package:vilvia/features/auth/data/auth_service.dart';
import 'package:vilvia/features/home/presentation/screens/home_screen.dart';

User user(String id, {String? email}) => User(
  id: id,
  appMetadata: const {},
  userMetadata: const {},
  aud: 'authenticated',
  createdAt: '2026-01-01T00:00:00Z',
  email: email ?? '$id@example.com',
);

Session session(String id, {String token = 'token'}) =>
    Session(accessToken: token, tokenType: 'bearer', user: user(id));

class FakeAuthService extends AuthService {
  FakeAuthService(this.currentSession);

  @override
  Session? currentSession;
  final controller = StreamController<AuthState>.broadcast();
  int signOutCalls = 0;
  Future<void> Function()? signOutHandler;

  @override
  Stream<AuthState> get onAuthStateChange => controller.stream;

  void emit(Session? value) {
    currentSession = value;
    controller.add(
      AuthState(
        value == null
            ? AuthChangeEvent.signedOut
            : AuthChangeEvent.tokenRefreshed,
        value,
      ),
    );
  }

  @override
  Future<void> signOut() async {
    signOutCalls++;
    if (signOutHandler != null) {
      await signOutHandler!();
      return;
    }
    emit(null);
  }

  void dispose() => controller.close();
}

class FakeAccountApiClient extends AccountApiClient {
  FakeAccountApiClient(this.handler)
    : super(accessTokenProvider: () => 'token');
  final Future<AccountDeletionRequest> Function() handler;
  int calls = 0;

  @override
  Future<AccountDeletionRequest> requestAccountDeletion() {
    calls++;
    return handler();
  }
}

class ClosingAccountApiClient extends FakeAccountApiClient {
  ClosingAccountApiClient()
    : super(() async => accepted(AccountDeletionStatus.requested));

  bool closed = false;

  @override
  void close() => closed = true;
}

AccountDeletionRequest accepted(AccountDeletionStatus status) =>
    AccountDeletionRequest(status: status, requestedAt: DateTime.utc(2026));

void main() {
  Widget screen(FakeAuthService auth, FakeAccountApiClient api) => MaterialApp(
    home: AccountScreen(
      authService: auth,
      accountUserId: 'user-a',
      apiClient: api,
    ),
  );

  Future<void> openDialog(WidgetTester tester) async {
    await tester.tap(find.text('Delete account').last);
    await tester.pumpAndSettle();
  }

  Future<void> confirm(WidgetTester tester) async {
    await openDialog(tester);
    await tester.tap(find.text('Confirm deletion'));
    await tester.pump();
  }

  testWidgets('signed-in user reaches Account without breaking navigation', (
    tester,
  ) async {
    final auth = FakeAuthService(session('user-a'));
    await tester.pumpWidget(MaterialApp(home: HomeScreen(authService: auth)));
    await tester.pump();
    await tester.tap(find.text('user-a@example.com'));
    await tester.pumpAndSettle();
    expect(find.byType(AccountScreen), findsOneWidget);
    expect(find.text('Signed in as'), findsOneWidget);
    expect(find.text('user-a@example.com'), findsOneWidget);
    Navigator.of(tester.element(find.byType(AccountScreen))).pop();
    await tester.pumpAndSettle();
    expect(find.byType(HomeScreen), findsOneWidget);
    auth.dispose();
  });

  testWidgets('discloses policy and cancel sends no request', (tester) async {
    final auth = FakeAuthService(session('user-a'));
    final api = FakeAccountApiClient(
      () async => accepted(AccountDeletionStatus.requested),
    );
    await tester.pumpWidget(screen(auth, api));
    await openDialog(tester);
    expect(find.textContaining('authored Posts'), findsOneWidget);
    expect(find.textContaining('authored Comments'), findsOneWidget);
    expect(find.textContaining('reactions you created'), findsOneWidget);
    expect(find.textContaining('Reports you created'), findsOneWidget);
    expect(find.textContaining('threads below'), findsOneWidget);
    expect(find.textContaining('may not complete immediately'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(api.calls, 0);
    auth.dispose();
  });

  for (final status in AccountDeletionStatus.values) {
    testWidgets('accepted ${status.name} signs out initiating user once', (
      tester,
    ) async {
      final auth = FakeAuthService(session('user-a'));
      final api = FakeAccountApiClient(() async => accepted(status));
      await tester.pumpWidget(screen(auth, api));
      await confirm(tester);
      await tester.pumpAndSettle();
      expect(api.calls, 1);
      expect(auth.signOutCalls, 1);
      auth.dispose();
    });
  }

  testWidgets('duplicate submission is blocked while pending', (tester) async {
    final pending = Completer<AccountDeletionRequest>();
    final auth = FakeAuthService(session('user-a'));
    final api = FakeAccountApiClient(() => pending.future);
    await tester.pumpWidget(screen(auth, api));
    await confirm(tester);
    expect(api.calls, 1);
    expect(find.text('Requesting deletion…'), findsOneWidget);
    expect(
      tester
          .widget<FilledButton>(
            find.widgetWithText(FilledButton, 'Requesting deletion…'),
          )
          .onPressed,
      isNull,
    );
    pending.complete(accepted(AccountDeletionStatus.requested));
    await tester.pumpAndSettle();
    expect(api.calls, 1);
    auth.dispose();
  });

  testWidgets('failure leaves user signed in and retryable', (tester) async {
    var fail = true;
    final auth = FakeAuthService(session('user-a'));
    final api = FakeAccountApiClient(() async {
      if (fail) throw Exception();
      return accepted(AccountDeletionStatus.requested);
    });
    await tester.pumpWidget(screen(auth, api));
    await confirm(tester);
    await tester.pump();
    expect(auth.currentSession, isNotNull);
    expect(
      find.text('Could not request account deletion. Try again.'),
      findsOneWidget,
    );
    expect(find.text('Delete account'), findsWidgets);
    fail = false;
    await confirm(tester);
    await tester.pumpAndSettle();
    expect(api.calls, 2);
    expect(auth.signOutCalls, 1);
    auth.dispose();
  });

  testWidgets('same-user refresh preserves pending request', (tester) async {
    final pending = Completer<AccountDeletionRequest>();
    final auth = FakeAuthService(session('user-a'));
    final api = FakeAccountApiClient(() => pending.future);
    await tester.pumpWidget(screen(auth, api));
    await confirm(tester);
    auth.emit(session('user-a', token: 'refreshed'));
    await tester.pump();
    pending.complete(accepted(AccountDeletionStatus.requested));
    await tester.pumpAndSettle();
    expect(auth.signOutCalls, 1);
    auth.dispose();
  });

  for (final staleFailure in [false, true]) {
    testWidgets(
      'sign-out suppresses stale ${staleFailure ? 'failure' : 'success'}',
      (tester) async {
        final pending = Completer<AccountDeletionRequest>();
        final auth = FakeAuthService(session('user-a'));
        final api = FakeAccountApiClient(() => pending.future);
        await tester.pumpWidget(screen(auth, api));
        await confirm(tester);
        auth.emit(null);
        await tester.pump();
        staleFailure
            ? pending.completeError(Exception())
            : pending.complete(accepted(AccountDeletionStatus.requested));
        await tester.pumpAndSettle();
        expect(auth.signOutCalls, 0);
        expect(
          find.text('Could not request account deletion. Try again.'),
          findsNothing,
        );
        auth.dispose();
      },
    );
  }

  for (final staleFailure in [false, true]) {
    testWidgets(
      'account switch suppresses stale ${staleFailure ? 'failure' : 'success'}',
      (tester) async {
        final pending = Completer<AccountDeletionRequest>();
        final auth = FakeAuthService(session('user-a'));
        final api = FakeAccountApiClient(() => pending.future);
        await tester.pumpWidget(screen(auth, api));
        await confirm(tester);
        auth.emit(session('user-b'));
        await tester.pump();
        staleFailure
            ? pending.completeError(Exception())
            : pending.complete(accepted(AccountDeletionStatus.requested));
        await tester.pumpAndSettle();
        expect(auth.signOutCalls, 0);
        expect(auth.currentSession?.user.id, 'user-b');
        expect(
          find.text('Could not request account deletion. Try again.'),
          findsNothing,
        );
        auth.dispose();
      },
    );
  }

  testWidgets('disposal during request causes no stale UI work', (
    tester,
  ) async {
    final pending = Completer<AccountDeletionRequest>();
    final auth = FakeAuthService(session('user-a'));
    final api = FakeAccountApiClient(() => pending.future);
    await tester.pumpWidget(screen(auth, api));
    await confirm(tester);
    await tester.pumpWidget(const MaterialApp(home: SizedBox()));
    pending.completeError(Exception());
    await tester.pump();
    expect(tester.takeException(), isNull);
    expect(auth.signOutCalls, 0);
    auth.dispose();
  });

  testWidgets(
    'accepted deletion offers only sign-out retry after sign-out failure',
    (tester) async {
      final auth = FakeAuthService(session('user-a'))
        ..signOutHandler = () async => throw Exception('storage failure');
      final api = FakeAccountApiClient(
        () async => accepted(AccountDeletionStatus.requested),
      );
      await tester.pumpWidget(screen(auth, api));
      await confirm(tester);
      await tester.pump(const Duration(milliseconds: 300));

      expect(api.calls, 1);
      expect(find.text('Retry sign out'), findsOneWidget);
      expect(find.text('Sign out'), findsNothing);
      expect(find.text('Confirm deletion'), findsNothing);
      expect(
        find.text(
          'Deletion was requested, but sign-out failed. Please sign out.',
        ),
        findsOneWidget,
      );

      auth.signOutHandler = () async => auth.emit(null);
      await tester.tap(find.text('Retry sign out'));
      await tester.pumpAndSettle();
      expect(api.calls, 1);
      expect(auth.signOutCalls, 2);
      auth.dispose();
    },
  );

  testWidgets('account switch suppresses stale sign-out failure', (
    tester,
  ) async {
    final signOut = Completer<void>();
    final auth = FakeAuthService(session('user-a'))
      ..signOutHandler = () => signOut.future;
    final api = FakeAccountApiClient(
      () async => accepted(AccountDeletionStatus.requested),
    );
    await tester.pumpWidget(screen(auth, api));
    await confirm(tester);
    expect(auth.signOutCalls, 1);

    auth.emit(session('user-b'));
    await tester.pump();
    signOut.completeError(Exception());
    await tester.pumpAndSettle();
    expect(auth.currentSession?.user.id, 'user-b');
    expect(
      find.text(
        'Deletion was requested, but sign-out failed. Please sign out.',
      ),
      findsNothing,
    );
    auth.dispose();
  });

  testWidgets('replacement user remains after initiating sign-out completes', (
    tester,
  ) async {
    final signOut = Completer<void>();
    final auth = FakeAuthService(session('user-a'))
      ..signOutHandler = () => signOut.future;
    final api = FakeAccountApiClient(
      () async => accepted(AccountDeletionStatus.requested),
    );
    await tester.pumpWidget(screen(auth, api));
    await confirm(tester);
    auth.emit(session('user-b'));
    await tester.pump();
    signOut.complete();
    await tester.pumpAndSettle();
    expect(auth.currentSession?.user.id, 'user-b');
    expect(auth.signOutCalls, 1);
    auth.dispose();
  });

  testWidgets('covered Account removal never pops the covering route', (
    tester,
  ) async {
    final auth = FakeAuthService(session('user-a'));
    final api = FakeAccountApiClient(
      () async => accepted(AccountDeletionStatus.requested),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (homeContext) => Scaffold(
            body: TextButton(
              onPressed: () => Navigator.of(homeContext).push(
                MaterialPageRoute(
                  builder: (_) => AccountScreen(
                    authService: auth,
                    accountUserId: 'user-a',
                    apiClient: api,
                  ),
                ),
              ),
              child: const Text('Open account'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open account'));
    await tester.pumpAndSettle();
    final accountContext = tester.element(find.byType(AccountScreen));
    Navigator.of(accountContext).push(
      MaterialPageRoute(
        builder: (_) => const Scaffold(body: Text('Covering route')),
      ),
    );
    await tester.pumpAndSettle();

    auth.emit(null);
    await tester.pumpAndSettle();
    expect(find.text('Covering route'), findsOneWidget);
    Navigator.of(tester.element(find.text('Covering route'))).pop();
    await tester.pumpAndSettle();
    expect(find.text('Open account'), findsOneWidget);
    expect(find.byType(AccountScreen), findsNothing);
    auth.dispose();
  });

  testWidgets('signed-out Account exposes no identity or deletion action', (
    tester,
  ) async {
    final auth = FakeAuthService(null);
    final api = FakeAccountApiClient(
      () async => accepted(AccountDeletionStatus.requested),
    );
    await tester.pumpWidget(screen(auth, api));
    await tester.pump();
    expect(find.text('user-a@example.com'), findsNothing);
    expect(find.text('Delete account'), findsNothing);
    expect(api.calls, 0);
    auth.dispose();
  });

  for (final response in [
    http.Response(
      '{"status":"bad","requested_at":"2026-09-03T10:00:00Z"}',
      202,
    ),
    http.Response('{"detail":"denied"}', 409),
  ]) {
    testWidgets(
      '${response.statusCode} invalid response does not sign out and is retryable',
      (tester) async {
        final auth = FakeAuthService(session('user-a'));
        final api = AccountApiClient(
          baseUrl: 'http://localhost',
          accessTokenProvider: () => 'token',
          client: MockClient((_) async => response),
        );
        await tester.pumpWidget(
          MaterialApp(
            home: AccountScreen(
              authService: auth,
              accountUserId: 'user-a',
              apiClient: api,
            ),
          ),
        );
        await confirm(tester);
        await tester.pump();
        expect(auth.signOutCalls, 0);
        expect(auth.currentSession, isNotNull);
        expect(
          find.text('Could not request account deletion. Try again.'),
          findsOneWidget,
        );
        expect(find.text('Delete account'), findsWidgets);
        auth.dispose();
      },
    );
  }

  testWidgets('screen closes only an owned AccountApiClient', (tester) async {
    final auth = FakeAuthService(session('user-a'));
    final owned = ClosingAccountApiClient();
    await tester.pumpWidget(
      MaterialApp(
        home: AccountScreen(
          authService: auth,
          accountUserId: 'user-a',
          apiClientFactory: () => owned,
        ),
      ),
    );
    await tester.pumpWidget(const MaterialApp(home: SizedBox()));
    expect(owned.closed, isTrue);

    final injected = ClosingAccountApiClient();
    await tester.pumpWidget(
      MaterialApp(
        home: AccountScreen(
          authService: auth,
          accountUserId: 'user-a',
          apiClient: injected,
        ),
      ),
    );
    await tester.pumpWidget(const MaterialApp(home: SizedBox()));
    expect(injected.closed, isFalse);
    auth.dispose();
  });
}
