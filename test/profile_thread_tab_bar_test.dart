import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:mobile/l10n/app_localizations.dart';
import 'package:mobile/widgets/profile_thread_tab_bar.dart';

void main() {
  testWidgets('ProfileThreadTabBar renders thread, reply, and map tabs', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
        ],
        supportedLocales: AppLocalizations.supportedLocales,
        home: DefaultTabController(
          length: 3,
          child: Builder(
            builder: (context) => Scaffold(
              body: ProfileThreadTabBar(
                controller: DefaultTabController.of(context),
              ),
            ),
          ),
        ),
      ),
    );

    expect(find.text('THREADS'), findsOneWidget);
    expect(find.text('REPLIES'), findsOneWidget);
    expect(find.text('MAP'), findsOneWidget);
  });
}
