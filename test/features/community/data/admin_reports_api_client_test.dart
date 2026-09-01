import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:vilvia/features/community/data/admin_report.dart';
import 'package:vilvia/features/community/data/community_api_client.dart';

void main() {
  const baseUrl = 'http://localhost';

  Map<String, dynamic> reportJson({
    String status = 'pending',
    bool isHidden = false,
  }) => {
    'id': 'report-1',
    'reason': 'Unsafe advice',
    'status': status,
    'created_at': '2026-08-30T10:00:00Z',
    'updated_at': '2026-08-30T10:00:00Z',
    'target_kind': 'comment',
    'target_id': 'comment-1',
    'target_is_hidden': isHidden,
    'post': null,
    'comment': {
      'id': 'comment-1',
      'body': 'Reported comment',
      'post_id': 'post-1',
      'post_title': 'Parent post',
    },
  };

  test('lists reports with auth, filter, and bounded pagination', () async {
    final api = CommunityApiClient(
      baseUrl: baseUrl,
      accessToken: () => 'token',
      client: MockClient((request) async {
        expect(request.method, 'GET');
        expect(request.url.path, '/reports');
        expect(request.url.queryParameters, {
          'status': 'reviewed',
          'limit': '25',
          'offset': '5',
        });
        expect(request.headers['Authorization'], 'Bearer token');
        return http.Response(jsonEncode([reportJson(status: 'reviewed')]), 200);
      }),
    );

    final reports = await api.getAdminReports(
      status: ReportStatus.reviewed,
      limit: 25,
      offset: 5,
    );

    expect(reports.single.status, ReportStatus.reviewed);
    expect(reports.single.targetKind, ReportTargetKind.comment);
    expect(reports.single.comment!.postTitle, 'Parent post');
    expect(reports.single.post, isNull);
  });

  test('updates report status through the exact authenticated path', () async {
    final api = CommunityApiClient(
      baseUrl: baseUrl,
      accessToken: () => 'token',
      client: MockClient((request) async {
        expect(request.method, 'PUT');
        expect(request.url.path, '/reports/report-1/status');
        expect(request.headers['Authorization'], 'Bearer token');
        expect(jsonDecode(request.body), {'status': 'dismissed'});
        return http.Response(jsonEncode(reportJson(status: 'dismissed')), 200);
      }),
    );

    final report = await api.updateAdminReportStatus(
      reportId: 'report-1',
      status: ReportStatus.dismissed,
    );

    expect(report.status, ReportStatus.dismissed);
  });

  test(
    'updates target visibility through the exact authenticated path',
    () async {
      final api = CommunityApiClient(
        baseUrl: baseUrl,
        accessToken: () => 'token',
        client: MockClient((request) async {
          expect(request.method, 'PUT');
          expect(request.url.path, '/reports/report-1/target-visibility');
          expect(request.headers['Authorization'], 'Bearer token');
          expect(jsonDecode(request.body), {'is_hidden': true});
          return http.Response(jsonEncode(reportJson(isHidden: true)), 200);
        }),
      );

      final report = await api.updateAdminReportTargetVisibility(
        reportId: 'report-1',
        isHidden: true,
      );

      expect(report.targetIsHidden, isTrue);
    },
  );

  test('admin calls fail locally without a session', () async {
    final api = CommunityApiClient(baseUrl: baseUrl);

    await expectLater(api.getAdminReports(), throwsStateError);
    await expectLater(
      api.updateAdminReportStatus(
        reportId: 'report-1',
        status: ReportStatus.reviewed,
      ),
      throwsStateError,
    );
    await expectLater(
      api.updateAdminReportTargetVisibility(
        reportId: 'report-1',
        isHidden: true,
      ),
      throwsStateError,
    );
  });

  test('admin calls throw on unsuccessful responses', () async {
    final api = CommunityApiClient(
      baseUrl: baseUrl,
      accessToken: () => 'token',
      client: MockClient((_) async => http.Response('', 403)),
    );

    await expectLater(api.getAdminReports(), throwsException);
    await expectLater(
      api.updateAdminReportStatus(
        reportId: 'report-1',
        status: ReportStatus.reviewed,
      ),
      throwsException,
    );
    await expectLater(
      api.updateAdminReportTargetVisibility(
        reportId: 'report-1',
        isHidden: true,
      ),
      throwsException,
    );
  });

  group('AdminReport response validation', () {
    test('accepts coherent Post context', () {
      final json = reportJson()
        ..['target_kind'] = 'post'
        ..['target_id'] = 'post-1'
        ..['post'] = {
          'id': 'post-1',
          'title': 'Post title',
          'body': 'Post body',
        }
        ..['comment'] = null;

      final parsed = AdminReport.fromJson(json);

      expect(parsed.targetKind, ReportTargetKind.post);
      expect(parsed.post!.id, parsed.targetId);
      expect(parsed.comment, isNull);
    });

    test('rejects an unknown target kind', () {
      final json = reportJson()..['target_kind'] = 'event';

      expect(() => AdminReport.fromJson(json), throwsFormatException);
    });

    test('rejects both target contexts being present', () {
      final json = reportJson()
        ..['post'] = {'id': 'comment-1', 'title': 'Post', 'body': 'Body'};

      expect(() => AdminReport.fromJson(json), throwsFormatException);
    });

    test('rejects neither target context being present', () {
      final json = reportJson()..['comment'] = null;

      expect(() => AdminReport.fromJson(json), throwsFormatException);
    });

    test('rejects a context ID that does not match target ID', () {
      final json = reportJson()..['target_id'] = 'different-comment';

      expect(() => AdminReport.fromJson(json), throwsFormatException);
    });

    test('rejects malformed timestamps', () {
      final json = reportJson()..['created_at'] = 'not-a-timestamp';

      expect(() => AdminReport.fromJson(json), throwsFormatException);
    });

    test('rejects missing or non-Boolean visibility', () {
      final missing = reportJson()..remove('target_is_hidden');
      final malformed = reportJson()..['target_is_hidden'] = 'false';

      expect(() => AdminReport.fromJson(missing), throwsFormatException);
      expect(() => AdminReport.fromJson(malformed), throwsFormatException);
    });

    test('rejects incorrect JSON value types as FormatException', () {
      final json = reportJson()..['reason'] = 42;

      expect(() => AdminReport.fromJson(json), throwsFormatException);
    });

    test(
      'API surfaces malformed successful payloads as FormatException',
      () async {
        final malformed = reportJson()..['target_id'] = 'wrong-id';
        final api = CommunityApiClient(
          baseUrl: baseUrl,
          accessToken: () => 'token',
          client: MockClient(
            (_) async => http.Response(jsonEncode([malformed]), 200),
          ),
        );

        await expectLater(api.getAdminReports(), throwsFormatException);
      },
    );
  });
}
