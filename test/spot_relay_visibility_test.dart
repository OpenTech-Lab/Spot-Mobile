import 'package:flutter_test/flutter_test.dart';

import 'package:mobile/features/event/event_repository.dart';
import 'package:mobile/features/nostr/nostr_service.dart';
import 'package:mobile/models/event_model.dart';
import 'package:mobile/models/media_post.dart';
import 'package:mobile/models/wallet_model.dart';

void main() {
  group('Spot relay visibility', () {
    test('publishMediaPost includes indexed and legacy Spot markers', () async {
      final service = NostrService(relayUrls: const []);
      final wallet = _wallet();
      final post = MediaPost(
        id: 'hash-a',
        pubkey: wallet.publicKeyHex,
        contentHashes: const ['hash-a'],
        capturedAt: DateTime.utc(2026, 3, 23, 0, 0),
        eventTags: const ['tokyo'],
        caption: 'Test post',
        nostrEventId: 'hash-a',
      );

      final event = await service.publishMediaPost(post, wallet);

      expect(event.getTagValue(spotRelayMarkerTag), spotEventOrigin);
      expect(event.getTagValue(legacySpotAppTag), spotEventOrigin);
      expect(event.getAllTagValues('t'), ['tokyo']);
      expect(event.content, contains('Test post'));
    });

    test(
      'buildSpotPostFilters includes indexed, legacy, and fallback filters',
      () {
        final filters = EventRepository.buildSpotPostFilters(
          authors: const ['author-1'],
          since: 10,
          until: 20,
          limit: 30,
          includeGenericFallback: true,
        );

        expect(filters, hasLength(3));
        expect(filters[0].toJson()['#d'], [spotEventOrigin]);
        expect(filters[1].toJson()['#app'], [spotEventOrigin]);
        expect(filters[2].toJson().containsKey('#d'), isFalse);
        expect(filters[2].toJson().containsKey('#app'), isFalse);
        expect(filters[2].toJson()['authors'], ['author-1']);
        expect(filters[2].toJson()['since'], 10);
        expect(filters[2].toJson()['until'], 20);
      },
    );

    test('isSpotEvent accepts indexed and legacy markers', () {
      final indexedEvent = _eventWithTags([
        [spotRelayMarkerTag, spotEventOrigin],
      ]);
      final legacyEvent = _eventWithTags([
        [legacySpotAppTag, spotEventOrigin],
      ]);
      final foreignEvent = _eventWithTags([
        ['app', 'other-client'],
      ]);

      expect(EventRepository.isSpotEvent(indexedEvent), isTrue);
      expect(EventRepository.isSpotEvent(legacyEvent), isTrue);
      expect(EventRepository.isSpotEvent(foreignEvent), isFalse);
    });
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

NostrEvent _eventWithTags(List<List<String>> tags) => NostrEvent(
  id: 'id-1',
  pubkey: 'pubkey-1',
  createdAt: 1,
  kind: 1,
  tags: tags,
  content: '',
  sig: 'sig-1',
);
