import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:vilvia/features/information/data/information_api_client.dart';
import 'package:vilvia/features/information/data/resource.dart';
import 'package:vilvia/features/information/data/resource_detail.dart';
import 'package:vilvia/features/information/presentation/screens/resource_details_screen.dart';

// --- Stub helpers ---

ResourceDetail _fakeDetail({
  String title = 'Sleep Guide',
  String body = 'The full article body, with all the detail.',
  String sourceName = 'MedlinePlus.gov',
  String sourceUrl = 'https://medlineplus.gov/example.html',
}) {
  return ResourceDetail(
    resource: Resource(
      id: 'abc-123',
      title: title,
      summary: 'A short summary',
      category: 'sleep',
      stage: '0_6m',
      sourceName: sourceName,
      sourceUrl: sourceUrl,
      createdAt: DateTime(2024),
      updatedAt: DateTime(2024),
    ),
    body: body,
  );
}

class _StubApiClient extends InformationApiClient {
  final Future<ResourceDetail> Function() _fn;

  _StubApiClient(this._fn) : super(baseUrl: 'http://test');

  @override
  Future<ResourceDetail> getResource(String id) => _fn();
}

// --- Tests ---

void main() {
  Widget wrap(InformationApiClient client, {ValueChanged<Uri>? onLaunch}) {
    return MaterialApp(
      home: ResourceDetailsScreen(
        resourceId: 'abc-123',
        apiClient: client,
        onLaunchUrl: onLaunch == null
            ? null
            : (uri) async {
                onLaunch(uri);
              },
      ),
    );
  }

  testWidgets('shows loading indicator before response arrives',
      (tester) async {
    final client = _StubApiClient(() => Completer<ResourceDetail>().future);
    await tester.pumpWidget(wrap(client));

    expect(find.byType(CircularProgressIndicator), findsOneWidget);
  });

  testWidgets('shows title, category, stage, body, and source on success',
      (tester) async {
    final client = _StubApiClient(() async => _fakeDetail());
    await tester.pumpWidget(wrap(client));
    await tester.pumpAndSettle();

    expect(find.text('Sleep Guide'), findsOneWidget);
    expect(find.text('Sleep'), findsOneWidget);
    expect(find.text('0–6 Months'), findsOneWidget);
    expect(
      find.text('The full article body, with all the detail.'),
      findsOneWidget,
    );
    expect(find.text('MedlinePlus.gov'), findsOneWidget);
    expect(find.text('View original source'), findsOneWidget);
  });

  testWidgets('shows error message and retry button on failure',
      (tester) async {
    final client =
        _StubApiClient(() async => throw Exception('Network error'));
    await tester.pumpWidget(wrap(client));
    await tester.pumpAndSettle();

    expect(find.text('Failed to load resource.'), findsOneWidget);
    expect(find.text('Retry'), findsOneWidget);
  });

  testWidgets('retry button reloads and shows the resource', (tester) async {
    var callCount = 0;
    final client = _StubApiClient(() {
      callCount++;
      if (callCount == 1) return Future.error(Exception('First call fails'));
      return Future.value(_fakeDetail(title: 'Loaded After Retry'));
    });

    await tester.pumpWidget(wrap(client));
    await tester.pumpAndSettle();
    expect(find.text('Failed to load resource.'), findsOneWidget);

    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();
    expect(find.text('Loaded After Retry'), findsOneWidget);
  });

  testWidgets('back button pops the screen', (tester) async {
    final client = _StubApiClient(() async => _fakeDetail());

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => ResourceDetailsScreen(
                      resourceId: 'abc-123',
                      apiClient: client,
                    ),
                  ),
                ),
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    expect(find.byType(ResourceDetailsScreen), findsOneWidget);

    await tester.tap(find.byTooltip('Back'));
    await tester.pumpAndSettle();

    expect(find.byType(ResourceDetailsScreen), findsNothing);
    expect(find.text('Open'), findsOneWidget);
  });

  testWidgets(
      'tapping "View original source" invokes the launcher with the source url',
      (tester) async {
    Uri? launchedUri;
    final client = _StubApiClient(
      () async => _fakeDetail(sourceUrl: 'https://medlineplus.gov/foo.html'),
    );

    await tester.pumpWidget(
      wrap(client, onLaunch: (uri) => launchedUri = uri),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('View original source'));
    await tester.pumpAndSettle();

    expect(launchedUri, Uri.parse('https://medlineplus.gov/foo.html'));
  });
}
