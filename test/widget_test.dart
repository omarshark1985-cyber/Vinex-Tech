import 'package:flutter_test/flutter_test.dart';
import 'package:vinex_technology/main.dart';

void main() {
  testWidgets('App smoke test', (WidgetTester tester) async {
    await tester.pumpWidget(const VinexTechnologyApp());
    expect(find.byType(VinexTechnologyApp), findsOneWidget);
  });
}
