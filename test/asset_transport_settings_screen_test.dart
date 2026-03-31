import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:mobile/l10n/app_localizations.dart';
import 'package:mobile/screens/asset_transport_settings_screen.dart';

void main() {
  testWidgets('CDN fetch and upload default to enabled', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
        ],
        supportedLocales: AppLocalizations.supportedLocales,
        home: const AssetTransportSettingsScreen(),
      ),
    );

    final toggles = tester
        .widgetList<CupertinoSwitch>(
          find.byType(CupertinoSwitch, skipOffstage: false),
        )
        .toList();

    expect(toggles, hasLength(2));
    expect(toggles[0].value, isTrue);
    expect(toggles[1].value, isTrue);
  });
}
