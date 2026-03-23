import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:mobile/features/nostr/nostr_service.dart';
import 'package:mobile/models/media_post.dart';
import 'package:mobile/models/wallet_model.dart';
import 'package:mobile/screens/post_composer_screen.dart';

void main() {
  testWidgets('reply flow opens the same composer UI in reply mode', (
    tester,
  ) async {
    final wallet = _wallet();
    final replyTarget = _replyTarget(wallet.publicKeyHex);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () {
                showPostComposer(
                  context,
                  wallet: wallet,
                  nostrService: NostrService(relayUrls: const []),
                  replyToPost: replyTarget,
                  gpsLoader: () async => null,
                );
              },
              child: const Text('Reply'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Reply'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));

    expect(find.textContaining('Reply to'), findsOneWidget);
    expect(find.text('Write a reply…'), findsOneWidget);
    expect(find.text("What's happening?"), findsNothing);
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
  createdAt: DateTime.utc(2026, 3, 23),
);

MediaPost _replyTarget(String pubkey) => MediaPost(
  id: 'reply-target-id',
  pubkey: pubkey,
  contentHashes: const ['reply-target-id'],
  capturedAt: DateTime.utc(2026, 3, 23, 12),
  eventTags: const ['tokyo'],
  caption: 'Original thread',
  nostrEventId: 'reply-target-id',
);
