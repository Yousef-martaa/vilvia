import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:vilvia/features/auth/data/auth_service.dart';
import 'package:vilvia/features/community/data/admin_report.dart';
import 'package:vilvia/features/community/data/community_api_client.dart';
import 'package:vilvia/features/community/presentation/screens/admin_reports_screen.dart';

AdminReport report({
  String id = 'report-1',
  ReportStatus status = ReportStatus.pending,
  bool isHidden = false,
  ReportTargetKind targetKind = ReportTargetKind.comment,
  String? targetId,
}) => AdminReport(
  id: id,
  reason: 'Unsafe advice',
  status: status,
  createdAt: DateTime.utc(2026, 8, 30),
  updatedAt: DateTime.utc(2026, 8, 30),
  targetKind: targetKind,
  targetId:
      targetId ??
      (targetKind == ReportTargetKind.post ? 'post-1' : 'comment-1'),
  targetIsHidden: isHidden,
  post: targetKind == ReportTargetKind.post
      ? ReportPostContext(
          id: targetId ?? 'post-1',
          title: 'Reported post $id',
          body: 'Reported post body',
        )
      : null,
  comment: targetKind == ReportTargetKind.comment
      ? ReportCommentContext(
          id: targetId ?? 'comment-1',
          body: 'Reported comment',
          postId: 'post-1',
          postTitle: 'Parent post',
        )
      : null,
);

class _FakeClient extends CommunityApiClient {
  _FakeClient({required this.load, this.update, this.updateVisibility})
    : super(baseUrl: 'http://test');

  final Future<List<AdminReport>> Function() load;
  final Future<AdminReport> Function(ReportStatus status)? update;
  final Future<AdminReport> Function(String reportId, bool isHidden)?
  updateVisibility;
  int updateCalls = 0;
  int visibilityCalls = 0;

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

  @override
  Future<AdminReport> updateAdminReportTargetVisibility({
    required String reportId,
    required bool isHidden,
  }) {
    visibilityCalls++;
    return updateVisibility!(reportId, isHidden);
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
    expect(find.text('Visible'), findsOneWidget);
    expect(find.text('Hide'), findsOneWidget);
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

  testWidgets('uses authoritative visibility and supports restore', (
    tester,
  ) async {
    bool? requested;
    final client = _FakeClient(
      load: () async => [report()],
      updateVisibility: (_, isHidden) async {
        requested = isHidden;
        return report(isHidden: true);
      },
    );
    await tester.pumpWidget(wrap(client));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Hide'));
    await tester.pumpAndSettle();

    expect(requested, isTrue);
    expect(find.text('Hidden'), findsOneWidget);
    expect(find.text('Restore'), findsOneWidget);
  });

  for (final targetKind in ReportTargetKind.values) {
    testWidgets(
      'propagates ${targetKind.name} visibility only to reports sharing the target',
      (tester) async {
        tester.view.physicalSize = const Size(800, 1600);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final sharedTargetId = '${targetKind.name}-shared';
        final client = _FakeClient(
          load: () async => [
            report(
              id: 'report-1',
              targetKind: targetKind,
              targetId: sharedTargetId,
            ),
            report(
              id: 'report-2',
              targetKind: targetKind,
              targetId: sharedTargetId,
            ),
            report(
              id: 'report-3',
              targetKind: targetKind,
              targetId: '${targetKind.name}-other',
              isHidden: false,
            ),
          ],
          updateVisibility: (reportId, isHidden) async => report(
            id: reportId,
            status: ReportStatus.dismissed,
            isHidden: isHidden,
            targetKind: targetKind,
            targetId: sharedTargetId,
          ),
        );
        await tester.pumpWidget(wrap(client));
        await tester.pumpAndSettle();

        expect(find.text('Hide'), findsNWidgets(3));
        await tester.tap(find.text('Hide').first);
        await tester.pumpAndSettle();

        expect(find.text('Restore'), findsNWidgets(2));
        expect(find.text('Hide'), findsOneWidget);
        expect(find.text('Hidden'), findsNWidgets(2));
        expect(find.text('Visible'), findsOneWidget);
        expect(find.text('Status: dismissed'), findsOneWidget);
        expect(find.text('Review'), findsNWidgets(2));
      },
    );
  }

  testWidgets('a different report remains actionable during moderation', (
    tester,
  ) async {
    final firstPending = Completer<AdminReport>();
    final secondPending = Completer<AdminReport>();
    final client = _FakeClient(
      load: () async => [
        report(id: 'report-1', targetId: 'comment-1'),
        report(id: 'report-2', targetId: 'comment-2'),
      ],
      updateVisibility: (reportId, _) =>
          reportId == 'report-1' ? firstPending.future : secondPending.future,
    );
    await tester.pumpWidget(wrap(client));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Hide').first);
    await tester.pump();
    final remainingHide = tester.widget<OutlinedButton>(
      find.widgetWithText(OutlinedButton, 'Hide'),
    );
    expect(remainingHide.onPressed, isNotNull);
    await tester.tap(find.text('Hide'));
    await tester.pump();
    expect(client.visibilityCalls, 2);

    firstPending.complete(
      report(id: 'report-1', targetId: 'comment-1', isHidden: true),
    );
    secondPending.complete(
      report(id: 'report-2', targetId: 'comment-2', isHidden: true),
    );
    await tester.pumpAndSettle();
  });

  testWidgets('prevents status and visibility updates from overlapping', (
    tester,
  ) async {
    final pending = Completer<AdminReport>();
    final client = _FakeClient(
      load: () async => [report()],
      updateVisibility: (_, _) => pending.future,
      update: (_) async => report(status: ReportStatus.reviewed),
    );
    await tester.pumpWidget(wrap(client));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Hide'));
    await tester.pump();
    expect(find.text('Review'), findsOneWidget);
    final review = tester.widget<ElevatedButton>(
      find.widgetWithText(ElevatedButton, 'Review'),
    );
    expect(review.onPressed, isNull);
    await tester.tap(find.text('Review'));
    expect(client.updateCalls, 0);
    expect(client.visibilityCalls, 1);
    pending.complete(report(isHidden: true));
    await tester.pumpAndSettle();
  });

  testWidgets('restores visibility action and shows feedback after failure', (
    tester,
  ) async {
    final client = _FakeClient(
      load: () async => [report()],
      updateVisibility: (_, _) async => throw Exception('network'),
    );
    await tester.pumpWidget(wrap(client));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Hide'));
    await tester.pumpAndSettle();
    expect(find.text('Could not update content visibility.'), findsOneWidget);
    expect(find.text('Hide'), findsOneWidget);
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

  testWidgets('same-user token refresh preserves and completes moderation', (
    tester,
  ) async {
    final auth = _FakeAuthService();
    final pending = Completer<AdminReport>();
    await tester.pumpWidget(
      wrap(
        _FakeClient(
          load: () async => [report()],
          updateVisibility: (_, _) => pending.future,
        ),
        authService: auth,
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Hide'));
    await tester.pump();

    auth.emit(_session('admin-1'));
    await tester.pump();
    pending.complete(report(isHidden: true));
    await tester.pumpAndSettle();

    expect(find.byType(AdminReportsScreen), findsOneWidget);
    expect(find.text('Hidden'), findsOneWidget);
    expect(find.text('Restore'), findsOneWidget);
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

    testWidgets('${change.key} invalidates a pending visibility PUT', (
      tester,
    ) async {
      final auth = _FakeAuthService();
      final pending = Completer<AdminReport>();
      await tester.pumpWidget(
        wrap(
          _FakeClient(
            load: () async => [report()],
            updateVisibility: (_, _) => pending.future,
          ),
          authService: auth,
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Hide'));
      await tester.pump();

      auth.emit(change.value);
      await tester.pump();
      pending.complete(report(isHidden: true));
      await tester.pumpAndSettle();

      expect(find.text('Reported comment'), findsNothing);
      expect(find.text('Hidden'), findsNothing);
    });

    testWidgets('${change.key} suppresses a stale visibility failure', (
      tester,
    ) async {
      final auth = _FakeAuthService();
      final pending = Completer<AdminReport>();
      await tester.pumpWidget(
        wrap(
          _FakeClient(
            load: () async => [report()],
            updateVisibility: (_, _) => pending.future,
          ),
          authService: auth,
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Hide'));
      await tester.pump();

      auth.emit(change.value);
      await tester.pump();
      pending.completeError(Exception('stale failure'));
      await tester.pumpAndSettle();

      expect(find.byType(AdminReportsScreen), findsOneWidget);
      expect(find.byType(SnackBar), findsNothing);
      expect(find.text('Reported comment'), findsNothing);
      expect(find.byType(CircularProgressIndicator), findsNothing);
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
