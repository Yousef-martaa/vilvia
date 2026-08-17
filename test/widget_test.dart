import 'package:flutter_test/flutter_test.dart';
import 'package:vilvia/app/app.dart';

void main() {
  testWidgets('VilviaApp renders HomeScreen', (WidgetTester tester) async {
    await tester.pumpWidget(const VilviaApp());
    // Hero headline is always present, no async load involved.
    expect(
      find.text('“It takes a village to raise a child.”'),
      findsOneWidget,
    );
  });
}
