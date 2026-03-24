import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:mobile/features/nostr/nostr_service.dart';
import 'package:mobile/models/media_post.dart';
import 'package:mobile/models/wallet_model.dart';
import 'package:mobile/screens/thread_screen.dart';

void main() {
  test('buildThreadScreenRoute uses a CupertinoPageRoute for swipe-back', () {
    final route = buildThreadScreenRoute(
      rootPostId: 'post-id',
      initialPosts: [_post()],
      wallet: _wallet(),
      nostrService: NostrService(relayUrls: const []),
    );

    expect(route, isA<CupertinoPageRoute<void>>());
  });
}

WalletModel _wallet() => WalletModel(
  privateKeyHex:
      '0000000000000000000000000000000000000000000000000000000000000001',
  publicKeyHex:
      '1111111111111111111111111111111111111111111111111111111111111111',
  npub: 'npub1test',
  mnemonic: const ['test'],
  deviceId: 'device-1',
  isRevoked: false,
  createdAt: DateTime.utc(2026, 3, 24),
);

MediaPost _post() => MediaPost(
  id: 'post-id',
  pubkey: 'pubkey',
  contentHashes: const ['post-id'],
  capturedAt: DateTime.utc(2026, 3, 24),
  eventTags: const ['tokyo'],
  nostrEventId: 'post-id',
);
