import 'package:flutter_test/flutter_test.dart';

import 'package:mobile/main.dart';

void main() {
  testWidgets('Spot app shows ALTCHA gate before onboarding', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const SpotApp());

    expect(find.text('Verifying…'), findsOneWidget);
    expect(find.text('Protected by ALTCHA'), findsOneWidget);
  });
}
