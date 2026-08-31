import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:vilvia/features/auth/data/auth_service.dart';
import 'package:vilvia/features/community/data/admin_report.dart';
import 'package:vilvia/features/community/data/community_api_client.dart';
import 'package:vilvia/features/community/presentation/screens/admin_reports_screen.dart';

AdminReport report({ReportStatus status = ReportStatus.pending}) => AdminReport(
  id: 'report-1',
  reason: 'Unsafe advice',
  status: status,
  createdAt: DateTime.utc(2026, 8, 30),
  updatedAt: DateTime.utc(2026, 8, 30),
  targetKind: ReportTargetKind.comment,
  targetId: 'comment-1',
  comment: const ReportCommentContext(
    id: 'comment-1',
    body: 'Reported comment',
    postId: 'post-1',
    postTitle: 'Parent post',
  ),
);

class _FakeClient extends CommunityApiClient {
  _FakeClient({required this.load, this.update})
    : super(baseUrl: 'http://test');

  final Future<List<AdminReport>> Function() load;
  final Future<AdminReport> Function(ReportStatus status)? update;
  int updateCalls = 0;

  @override
  Future<List<AdminReport>> getAdminReports({
    ReportStatus status = ReportStatus.pending,
    int limit = 50,
    int offset = 0,
  }) => load();

  @override
  Future<AdminReport> updateAdminReportStatus({
    required String reportId,
    required ReportStatus status,
  }) {
    updateCalls++;
    return update!(status);
  }
}

Session _session(String userId) => Session(
  accessToken: 'token-$userId',
  tokenType: 'bearer',
  user: User(
    id: userId,
    appMetadata: const {},
    userMetadata: const {},
    aud: 'authenticated',
    createdAt: '2026-08-22T00:00:00Z',
  ),
);

class _FakeAuthService extends AuthService {
  final _controller = StreamController<AuthState>.broadcast();

  @override
  Stream<AuthState> get onAuthStateChange => _controller.stream;

  void emit(Session? session) {
    _controller.add(AuthState(AuthChangeEvent.signedIn, session));
  }

  bool get hasListener => _controller.hasListener;

  Future<void> close() => _controller.close();
}

void main() {
  Widget wrap(_FakeClient client, {_FakeAuthService? authService}) {
    final auth = authService ?? _FakeAuthService();
    addTearDown(auth.close);
    return MaterialApp(
      home: AdminReportsScreen(
        apiClient: client,
        authService: auth,
        adminUserId: 'admin-1',
      ),
    );
  }

  testWidgets('shows loading then safe report context and actions', (
    tester,
  ) async {
    final completer = Completer<List<AdminReport>>();
    final client = _FakeClient(load: () => completer.future);
    await tester.pumpWidget(wrap(client));
    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    completer.complete([report()]);
    await tester.pumpAndSettle();
    expect(find.text('Comment on Parent post'), findsOneWidget);
    expect(find.text('Reported comment'), findsOneWidget);
    expect(find.text('Reason: Unsafe advice'), findsOneWidget);
    expect(find.text('Review'), findsOneWidget);
    expect(find.text('Dismiss'), findsOneWidget);
  });

  testWidgets('shows empty state', (tester) async {
    await tester.pumpWidget(wrap(_FakeClient(load: () async => [])));
    await tester.pumpAndSettle();
    expect(find.text('No pending reports.'), findsOneWidget);
  });

  testWidgets('shows error and retries successfully', (tester) async {
    var calls = 0;
    final client = _FakeClient(
      load: () async {
        calls++;
        if (calls == 1) throw Exception('network');
        return [report()];
      },
    );
    await tester.pumpWidget(wrap(client));
    await tester.pumpAndSettle();
    expect(find.text('Failed to load reports.'), findsOneWidget);

    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();
    expect(find.text('Reported comment'), findsOneWidget);
    expect(calls, 2);
  });

  testWidgets('disables both actions while one update is pending', (
    tester,
  ) async {
    final pending = Completer<AdminReport>();
    final client = _FakeClient(
      load: () async => [report()],
      update: (_) => pending.future,
    );
    await tester.pumpWidget(wrap(client));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Review'));
    await tester.tap(find.text('Review'));
    await tester.pump();
    expect(find.text('Review'), findsNothing);
    expect(find.text('Dismiss'), findsNothing);
    expect(client.updateCalls, 1);

    pending.complete(report(status: ReportStatus.reviewed));
    await tester.pumpAndSettle();
    expect(find.text('Status: reviewed'), findsOneWidget);
  });

  testWidgets('uses authoritative response after dismissal', (tester) async {
    ReportStatus? requested;
    final client = _FakeClient(
      load: () async => [report()],
      update: (status) async {
        requested = status;
        return report(status: ReportStatus.dismissed);
      },
    );
    await tester.pumpWidget(wrap(client));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Dismiss'));
    await tester.pumpAndSettle();
    expect(requested, ReportStatus.dismissed);
    expect(find.text('Status: dismissed'), findsOneWidget);
  });

  testWidgets('restores actions and shows feedback after update failure', (
    tester,
  ) async {
    final client = _FakeClient(
      load: () async => [report()],
      update: (_) async => throw Exception('network'),
    );
    await tester.pumpWidget(wrap(client));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Review'));
    await tester.pumpAndSettle();
    expect(find.text('Could not update report.'), findsOneWidget);
    expect(find.text('Review'), findsOneWidget);
  });

  for (final change in <String, Session?>{
    'sign-out': null,
    'account switch': _session('other-user'),
  }.entries) {
    testWidgets('${change.key} clears an open queue and removes the route', (
      tester,
    ) async {
      final auth = _FakeAuthService();
      final client = _FakeClient(load: () async => [report()]);
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => AdminReportsScreen(
                    apiClient: client,
                    authService: auth,
                    adminUserId: 'admin-1',
                  ),
                ),
              ),
              child: const Text('Open'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      expect(find.text('Reported comment'), findsOneWidget);

      auth.emit(change.value);
      await tester.pumpAndSettle();

      expect(find.byType(AdminReportsScreen), findsNothing);
      expect(find.text('Reported comment'), findsNothing);
      await auth.close();
    });

    testWidgets('${change.key} invalidates a pending initial GET', (
      tester,
    ) async {
      final auth = _FakeAuthService();
      final pending = Completer<List<AdminReport>>();
      await tester.pumpWidget(
        wrap(_FakeClient(load: () => pending.future), authService: auth),
      );

      auth.emit(change.value);
      await tester.pump();
      pending.complete([report()]);
      await tester.pumpAndSettle();

      expect(find.text('Reported comment'), findsNothing);
      expect(find.text('Review'), findsNothing);
    });

    testWidgets('${change.key} invalidates a pending status PUT', (
      tester,
    ) async {
      final auth = _FakeAuthService();
      final pending = Completer<AdminReport>();
      await tester.pumpWidget(
        wrap(
          _FakeClient(
            load: () async => [report()],
            update: (_) => pending.future,
          ),
          authService: auth,
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Review'));
      await tester.pump();

      auth.emit(change.value);
      await tester.pump();
      pending.complete(report(status: ReportStatus.reviewed));
      await tester.pumpAndSettle();

      expect(find.text('Reported comment'), findsNothing);
      expect(find.text('Status: reviewed'), findsNothing);
    });
  }

  testWidgets('cancels its auth subscription on dispose', (tester) async {
    final auth = _FakeAuthService();
    await tester.pumpWidget(
      wrap(_FakeClient(load: () async => []), authService: auth),
    );
    await tester.pumpAndSettle();
    expect(auth.hasListener, isTrue);

    await tester.pumpWidget(const SizedBox());

    expect(auth.hasListener, isFalse);
  });
}
