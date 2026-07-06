import 'package:flutter_test/flutter_test.dart';
import 'package:vilvia/app/app.dart';

void main() {
  testWidgets('VilviaApp renders placeholder', (WidgetTester tester) async {
    await tester.pumpWidget(const VilviaApp());

    expect(find.text('Vilvia'), findsOneWidget);
  });
}
