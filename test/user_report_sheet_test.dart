import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:mobile/core/community_safety.dart';
import 'package:mobile/l10n/app_localizations.dart';
import 'package:mobile/widgets/user_report_sheet.dart';

Widget _localizedApp({required Widget home}) => MaterialApp(
  localizationsDelegates: const [
    AppLocalizations.delegate,
    GlobalMaterialLocalizations.delegate,
    GlobalWidgetsLocalizations.delegate,
  ],
  supportedLocales: AppLocalizations.supportedLocales,
  home: Scaffold(body: home),
);

void main() {
  testWidgets('submits the selected user report reason and details', (
    tester,
  ) async {
    UserReportReason? submittedReason;
    String? submittedDetails;

    await tester.pumpWidget(
      _localizedApp(
        home: UserReportSheet(
          closeOnSuccess: false,
          onSubmit: (reason, details) async {
            submittedReason = reason;
            submittedDetails = details;
          },
        ),
      ),
    );

    await tester.tap(find.text('Spam or scams'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byType(TextField),
      'Repeated scam links and bot replies.',
    );
    await tester.tap(find.text('Submit report'));
    await tester.pumpAndSettle();

    expect(submittedReason, UserReportReason.spam);
    expect(submittedDetails, 'Repeated scam links and bot replies.');
  });
}
