import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:mobile/models/wallet_model.dart';
import 'package:mobile/screens/settings_screen.dart';

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
      MaterialApp(home: SettingsScreen(wallet: _wallet())),
    );

    expect(find.text('Favorite Topics'), findsOneWidget);

    await tester.tap(find.text('Favorite Topics'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));

    expect(
      find.text('Pick at least 3 topics to personalise your For You feed.'),
      findsOneWidget,
    );
  });
}

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
