import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:mobile/models/wallet_model.dart';
import 'package:mobile/screens/wallet_screen.dart';

void main() {
  testWidgets(
    'account screen hides legacy migration details and shows delete action',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(home: WalletScreen(wallet: _wallet())),
      );

      expect(find.text('Account'), findsOneWidget);
      expect(find.text('Public key'), findsNothing);
      expect(find.text('Recovery phrase'), findsNothing);
      expect(find.text('Move to new device'), findsNothing);
      expect(find.text('Generate migration QR'), findsNothing);
      expect(find.text('Delete this account'), findsOneWidget);
    },
  );
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
