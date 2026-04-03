import 'package:flutter_test/flutter_test.dart';

import 'package:mobile/features/metadata/metadata_service.dart';
import 'package:mobile/models/profile_model.dart';
import 'package:mobile/models/wallet_model.dart';

void main() {
  group('isProfileSessionCompatibleWithWallet', () {
    final wallet = _wallet();

    test('accepts a fresh anonymous profile with no bound identity yet', () {
      const profile = ProfileModel(id: 'profile-id');

      expect(isProfileSessionCompatibleWithWallet(profile, wallet), isTrue);
    });

    test('accepts a profile bound to the same wallet pubkey and device', () {
      final profile = ProfileModel(
        id: 'profile-id',
        legacyPubkey: wallet.publicKeyHex,
        deviceId: wallet.deviceId,
      );

      expect(isProfileSessionCompatibleWithWallet(profile, wallet), isTrue);
    });

    test('accepts a matching legacy pubkey even when device id is missing', () {
      final profile = ProfileModel(
        id: 'profile-id',
        legacyPubkey: wallet.publicKeyHex,
      );

      expect(isProfileSessionCompatibleWithWallet(profile, wallet), isTrue);
    });

    test('rejects a profile from another wallet on the same device', () {
      final profile = ProfileModel(
        id: 'profile-id',
        legacyPubkey: 'different-pubkey',
        deviceId: wallet.deviceId,
      );

      expect(isProfileSessionCompatibleWithWallet(profile, wallet), isFalse);
    });

    test(
      'rejects a profile from another device for the same wallet pubkey',
      () {
        final profile = ProfileModel(
          id: 'profile-id',
          legacyPubkey: wallet.publicKeyHex,
          deviceId: 'device-b',
        );

        expect(isProfileSessionCompatibleWithWallet(profile, wallet), isFalse);
      },
    );

    test('rejects a missing profile row', () {
      expect(isProfileSessionCompatibleWithWallet(null, wallet), isFalse);
    });
  });
}

WalletModel _wallet() => WalletModel(
  privateKeyHex: 'priv',
  publicKeyHex: 'pubkey-a',
  npub: 'npub-a',
  mnemonic: const ['one', 'two', 'three'],
  deviceId: 'device-a',
  isRevoked: false,
  createdAt: DateTime.utc(2026, 4, 3),
);
