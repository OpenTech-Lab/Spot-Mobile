import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:mobile/l10n/app_localizations.dart';
import 'package:mobile/models/profile_model.dart';
import 'package:mobile/models/wallet_model.dart';
import 'package:mobile/screens/settings_screen.dart';

Widget _localizedApp({required Widget home}) => MaterialApp(
  localizationsDelegates: const [
    AppLocalizations.delegate,
    GlobalMaterialLocalizations.delegate,
    GlobalWidgetsLocalizations.delegate,
  ],
  supportedLocales: AppLocalizations.supportedLocales,
  home: home,
);

void main() {
  test('favoriteTopicsSummary formats empty, short, and long selections', () {
    expect(favoriteTopicsSummary(const []), 'Not set');
    expect(
      favoriteTopicsSummary(const ['tokyo', 'breaking']),
      '#tokyo, #breaking',
    );
    expect(
      favoriteTopicsSummary(const ['tokyo', 'breaking', 'weather']),
      '#tokyo, #breaking +1',
    );
  });

  testWidgets('settings can open the favorite topics editor', (tester) async {
    await tester.pumpWidget(
      _localizedApp(
        home: SettingsScreen(
          wallet: _wallet(),
          loadProfileSettings: (_) async => _profile(),
          readSafeModeEnabled: () => true,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Favorite Topics'), findsOneWidget);

    await tester.tap(find.text('Favorite Topics'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));

    expect(
      find.text('Pick at least 3 topics to personalise your For You feed.'),
      findsOneWidget,
    );
  });

  testWidgets('settings exposes a logout action', (tester) async {
    await tester.pumpWidget(
      _localizedApp(
        home: SettingsScreen(
          wallet: _wallet(),
          loadProfileSettings: (_) async => _profile(),
          readSafeModeEnabled: () => true,
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(
      find.text('Log Out'),
      200,
      scrollable: find.byType(Scrollable),
    );
    await tester.drag(find.byType(Scrollable), const Offset(0, -80));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Log Out'));
    await tester.pumpAndSettle();

    expect(find.text('Log out?'), findsOneWidget);
    expect(
      find.text(
        'Before logging out, make sure you have saved your 12-word recovery '
        'phrase. You will need it to restore this same identity later. '
        'Logging out will sign you out on this device and erase local app '
        'data. Your Supabase account and remote posts will remain intact.',
      ),
      findsOneWidget,
    );
  });

  testWidgets('settings exposes profile visibility switches', (tester) async {
    await tester.pumpWidget(
      _localizedApp(
        home: SettingsScreen(
          wallet: _wallet(),
          loadProfileSettings: (_) async => _profile(
            areThreadsPublic: true,
            areRepliesPublic: false,
            isFootprintMapPublic: true,
          ),
          readSafeModeEnabled: () => true,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Public Threads'), findsOneWidget);
    expect(find.text('Public Replies'), findsOneWidget);
    expect(find.text('Footprint Map'), findsOneWidget);
    expect(find.text('ACTIVITY'), findsNothing);
    expect(find.text('PRIVACY'), findsOneWidget);

    final switches = tester.widgetList<Switch>(find.byType(Switch)).toList();
    expect(switches, hasLength(3));
    expect(switches[0].value, isTrue);
    expect(switches[1].value, isTrue);
    expect(switches[2].value, isFalse);
  });

  testWidgets('settings saves updated thread visibility from switch row', (
    tester,
  ) async {
    bool? savedThreadsPublic;

    await tester.pumpWidget(
      _localizedApp(
        home: SettingsScreen(
          wallet: _wallet(),
          loadProfileSettings: (_) async => _profile(areThreadsPublic: true),
          readSafeModeEnabled: () => true,
          saveProfileVisibility:
              (
                _, {
                bool? threadsPublic,
                bool? repliesPublic,
                bool? footprintMapPublic,
              }) async {
                savedThreadsPublic = threadsPublic;
                return _profile(areThreadsPublic: threadsPublic ?? true);
              },
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Public Threads'));
    await tester.pumpAndSettle();

    expect(savedThreadsPublic, isFalse);
  });

  testWidgets('settings exposes the my activity menu', (tester) async {
    await tester.pumpWidget(
      _localizedApp(
        home: SettingsScreen(
          wallet: _wallet(),
          loadProfileSettings: (_) async => _profile(),
          readSafeModeEnabled: () => true,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('View My Activity'), findsOneWidget);

    await tester.tap(find.text('View My Activity'));
    await tester.pumpAndSettle();

    expect(find.text('Posted Threads'), findsOneWidget);
    expect(find.text('Replied Threads'), findsOneWidget);
  });

  testWidgets('settings exposes and saves the safe mode switch', (
    tester,
  ) async {
    bool? savedSafeModeEnabled;

    await tester.pumpWidget(
      _localizedApp(
        home: SettingsScreen(
          wallet: _wallet(),
          loadProfileSettings: (_) async => _profile(),
          readSafeModeEnabled: () => true,
          saveSafeModeEnabled: (enabled) async {
            savedSafeModeEnabled = enabled;
          },
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(
      find.text('Safe Mode'),
      200,
      scrollable: find.byType(Scrollable),
    );
    await tester.pumpAndSettle();

    expect(find.text('Safe Mode'), findsOneWidget);

    await tester.tap(find.text('Safe Mode'));
    await tester.pumpAndSettle();

    expect(savedSafeModeEnabled, isFalse);
  });
}

ProfileModel _profile({
  bool areThreadsPublic = true,
  bool areRepliesPublic = true,
  bool isFootprintMapPublic = false,
}) => ProfileModel(
  id: 'user-1',
  createdAt: DateTime.utc(2026, 3, 29, 10, 30),
  displayName: 'Citizen Tokyo',
  areThreadsPublic: areThreadsPublic,
  areRepliesPublic: areRepliesPublic,
  isFootprintMapPublic: isFootprintMapPublic,
);

WalletModel _wallet() => WalletModel(
  privateKeyHex:
      '1111111111111111111111111111111111111111111111111111111111111111',
  publicKeyHex:
      '2222222222222222222222222222222222222222222222222222222222222222',
  npub: 'npub1example',
  mnemonic: const [
    'alpha',
    'bravo',
    'charlie',
    'delta',
    'echo',
    'foxtrot',
    'golf',
    'hotel',
    'india',
    'juliet',
    'kilo',
    'lima',
  ],
  deviceId: 'device-1234567890',
  isRevoked: false,
  createdAt: DateTime.utc(2026, 3, 26, 10, 30),
);
