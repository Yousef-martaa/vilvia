import 'package:flutter_test/flutter_test.dart';
import 'package:vilvia/app/app.dart';

void main() {
  testWidgets('VilviaApp renders ResourcesScreen', (WidgetTester tester) async {
    await tester.pumpWidget(const VilviaApp());
    // AppBar title is always present regardless of load state
    expect(find.text('Resources'), findsOneWidget);
  });
}
