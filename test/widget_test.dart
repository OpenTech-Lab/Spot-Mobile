import 'package:flutter/widgets.dart';
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

  testWidgets('Spot app applies an injected locale override', (
    WidgetTester tester,
  ) async {
    final localeListenable = ValueNotifier<Locale?>(const Locale('ja'));

    await tester.pumpWidget(SpotApp(localeListenable: localeListenable));

    expect(find.text('確認中…'), findsOneWidget);
    expect(find.text('ALTCHAで保護済み'), findsOneWidget);
  });
}
