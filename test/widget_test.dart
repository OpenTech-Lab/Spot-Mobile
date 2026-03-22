import 'package:flutter_test/flutter_test.dart';

import 'package:mobile/main.dart';

void main() {
  testWidgets('Spot app shows onboarding when no wallet is loaded', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const SpotApp());

    expect(find.text('Spot'), findsOneWidget);
    expect(find.text('Get started'), findsOneWidget);
  });
}
