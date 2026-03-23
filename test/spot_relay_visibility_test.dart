import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

import 'package:mobile/features/event/event_repository.dart';
import 'package:mobile/features/nostr/nostr_service.dart';
import 'package:mobile/models/event_model.dart';
import 'package:mobile/models/media_post.dart';
import 'package:mobile/models/wallet_model.dart';

void main() {
  group('Spot relay visibility', () {
    _TestRelay? acceptedRelay;
    _TestRelay? rejectedRelay;

    tearDown(() async {
      await acceptedRelay?.close();
      await rejectedRelay?.close();
      acceptedRelay = null;
      rejectedRelay = null;
    });

    test('publishMediaPost includes indexed and legacy Spot markers', () async {
      acceptedRelay = await _TestRelay.start(name: 'accepted');
      final service = NostrService(relayUrls: [acceptedRelay!.url]);
      final wallet = _wallet();
      final post = _post();

      final event = await service.publishMediaPost(post, wallet);

      expect(event.getTagValue(spotRelayMarkerTag), spotEventOrigin);
      expect(event.getTagValue(legacySpotAppTag), spotEventOrigin);
      expect(
        event.getAllTagValues('t'),
        containsAll([spotDiscoveryHashtag, 'tokyo']),
      );
      expect(event.content, contains('Test post'));
      await service.disconnect();
    });

    test(
      'publishMediaPost marks text-only posts without media_hash tags',
      () async {
        acceptedRelay = await _TestRelay.start(name: 'accepted');
        final service = NostrService(relayUrls: [acceptedRelay!.url]);

        final event = await service.publishMediaPost(
          _post().copyWith(
            contentHashes: const ['temp-hash'],
            mediaPaths: const [],
            isTextOnly: true,
          ),
          _wallet(),
        );

        expect(event.getTagValue('text_only'), '1');
        expect(event.getAllTagValues('media_hash'), isEmpty);
        await service.disconnect();
      },
    );

    test(
      'publishMediaPost includes an inline preview for image posts',
      () async {
        acceptedRelay = await _TestRelay.start(name: 'accepted');
        final service = NostrService(relayUrls: [acceptedRelay!.url]);
        final tempDir = await Directory.systemTemp.createTemp(
          'spot-preview-test-',
        );
        addTearDown(() => tempDir.delete(recursive: true));

        final imageFile = File('${tempDir.path}/preview.jpg');
        final image = img.Image(width: 32, height: 32);
        await imageFile.writeAsBytes(img.encodeJpg(image, quality: 80));

        final event = await service.publishMediaPost(
          _post().copyWith(mediaPaths: [imageFile.path]),
          _wallet(),
        );

        final previewTag = event.tags.firstWhere(
          (tag) => tag.isNotEmpty && tag.first == 'preview',
        );

        expect(previewTag, hasLength(3));
        expect(previewTag[1], 'image/jpeg');
        expect(previewTag[2], isNotEmpty);
        await service.disconnect();
      },
    );

    test(
      'buildSpotPostFilters uses only indexed discovery tag plus fallback',
      () {
        final filters = EventRepository.buildSpotPostFilters(
          authors: const ['author-1'],
          since: 10,
          until: 20,
          limit: 30,
          includeGenericFallback: true,
        );

        expect(filters, hasLength(2));
        expect(filters[0].toJson()['#t'], [spotDiscoveryHashtag]);
        expect(filters[0].toJson().containsKey('#d'), isFalse);
        expect(filters[0].toJson().containsKey('#app'), isFalse);
        expect(filters[1].toJson().containsKey('#d'), isFalse);
        expect(filters[1].toJson().containsKey('#app'), isFalse);
        expect(filters[1].toJson().containsKey('#t'), isFalse);
        expect(filters[1].toJson()['authors'], ['author-1']);
        expect(filters[1].toJson()['since'], 10);
        expect(filters[1].toJson()['until'], 20);
      },
    );

    test(
      'buildSpotModerationFilters uses only indexed discovery tag plus fallback',
      () {
        final filters = EventRepository.buildSpotModerationFilters(
          authors: const ['author-1'],
          since: 10,
          until: 20,
          limit: 30,
          includeGenericFallback: true,
        );

        expect(filters, hasLength(2));
        expect(filters[0].toJson()['#t'], [spotDiscoveryHashtag]);
        expect(filters[0].toJson()['kinds'], [5, 1984]);
        expect(filters[0].toJson().containsKey('#d'), isFalse);
        expect(filters[0].toJson().containsKey('#app'), isFalse);
        expect(filters[1].toJson().containsKey('#t'), isFalse);
        expect(filters[1].toJson()['authors'], ['author-1']);
      },
    );

    test('isSpotEvent accepts indexed, legacy, and discovery markers', () {
      final indexedEvent = _eventWithTags([
        [spotRelayMarkerTag, spotEventOrigin],
      ]);
      final legacyEvent = _eventWithTags([
        [legacySpotAppTag, spotEventOrigin],
      ]);
      final discoveryEvent = _eventWithTags([
        ['t', spotDiscoveryHashtag],
      ]);
      final foreignEvent = _eventWithTags([
        ['app', 'other-client'],
      ]);

      expect(EventRepository.isSpotEvent(indexedEvent), isTrue);
      expect(EventRepository.isSpotEvent(legacyEvent), isTrue);
      expect(EventRepository.isSpotEvent(discoveryEvent), isTrue);
      expect(EventRepository.isSpotEvent(foreignEvent), isFalse);
    });

    test('nostrEventToPost strips the hidden Spot discovery hashtag', () {
      final event = _eventWithTags([
        [spotRelayMarkerTag, spotEventOrigin],
        ['t', spotDiscoveryHashtag],
        ['t', 'tokyo'],
        ['t', 'news'],
      ]);

      final post = EventRepository.nostrEventToPost(event);

      expect(post.eventTags, ['tokyo', 'news']);
    });

    test('nostrEventToPost keeps the inline preview for remote rendering', () {
      final event = _eventWithTags([
        [spotRelayMarkerTag, spotEventOrigin],
        ['t', spotDiscoveryHashtag],
        ['t', 'tokyo'],
        ['preview', 'image/jpeg', 'YWJj'],
      ]);

      final post = EventRepository.nostrEventToPost(event);

      expect(post.eventTags, ['tokyo']);
      expect(post.previewMimeType, 'image/jpeg');
      expect(post.previewBase64, 'YWJj');
    });

    test('connect only reports relays after websocket readiness', () async {
      acceptedRelay = await _TestRelay.start(name: 'accepted');
      rejectedRelay = await _TestRelay.start(name: 'rejected');

      final service = NostrService(
        relayUrls: [acceptedRelay!.url, rejectedRelay!.url],
      );

      final connectFuture = service.connect();
      expect(service.connectedRelays, isEmpty);

      await connectFuture;

      expect(service.connectedRelays.toSet(), {
        acceptedRelay!.url,
        rejectedRelay!.url,
      });
      await service.disconnect();
    });

    test('publishMediaPost succeeds when at least one relay accepts', () async {
      acceptedRelay = await _TestRelay.start(
        name: 'accepted',
        acceptEvents: true,
      );
      rejectedRelay = await _TestRelay.start(
        name: 'rejected',
        acceptEvents: false,
        okMessage: 'blocked: duplicate',
      );

      final service = NostrService(
        relayUrls: [acceptedRelay!.url, rejectedRelay!.url],
      );
      await service.connect();

      final event = await service.publishMediaPost(_post(), _wallet());

      expect(event.getTagValue(spotRelayMarkerTag), spotEventOrigin);
      expect(acceptedRelay!.receivedEventIds, contains(event.id));
      expect(rejectedRelay!.receivedEventIds, contains(event.id));
      await service.disconnect();
    });

    test('publishMediaPost throws when all relays reject the event', () async {
      acceptedRelay = await _TestRelay.start(
        name: 'reject-a',
        acceptEvents: false,
        okMessage: 'invalid: blocked',
      );
      rejectedRelay = await _TestRelay.start(
        name: 'reject-b',
        acceptEvents: false,
        okMessage: 'invalid: rate limited',
      );

      final service = NostrService(
        relayUrls: [acceptedRelay!.url, rejectedRelay!.url],
      );
      await service.connect();

      await expectLater(
        service.publishMediaPost(_post(), _wallet()),
        throwsA(
          isA<StateError>().having(
            (error) => error.toString(),
            'message',
            allOf(contains('No relay accepted'), contains('invalid')),
          ),
        ),
      );

      await service.disconnect();
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

MediaPost _post() => MediaPost(
  id: 'hash-a',
  pubkey: _wallet().publicKeyHex,
  contentHashes: const ['hash-a'],
  capturedAt: DateTime.utc(2026, 3, 23, 0, 0),
  eventTags: const ['tokyo'],
  caption: 'Test post',
  nostrEventId: 'hash-a',
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

class _TestRelay {
  _TestRelay._({
    required this.name,
    required this.server,
    required this.acceptEvents,
    required this.okMessage,
  });

  final String name;
  final HttpServer server;
  final bool acceptEvents;
  final String okMessage;
  final List<WebSocket> _sockets = [];
  final List<String> receivedEventIds = [];

  String get url => 'ws://${server.address.host}:${server.port}';

  static Future<_TestRelay> start({
    required String name,
    bool acceptEvents = true,
    String okMessage = 'saved',
  }) async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final relay = _TestRelay._(
      name: name,
      server: server,
      acceptEvents: acceptEvents,
      okMessage: okMessage,
    );
    relay._listen();
    return relay;
  }

  void _listen() {
    server.listen((request) async {
      final socket = await WebSocketTransformer.upgrade(request);
      _sockets.add(socket);
      socket.listen(
        (raw) {
          final data = jsonDecode(raw as String) as List<dynamic>;
          if (data.isEmpty) return;
          if (data.first == 'EVENT' && data.length >= 2) {
            final eventJson = Map<String, dynamic>.from(data[1] as Map);
            final eventId = eventJson['id'] as String;
            receivedEventIds.add(eventId);
            socket.add(jsonEncode(['OK', eventId, acceptEvents, okMessage]));
          }
        },
        onDone: () {
          _sockets.remove(socket);
        },
      );
    });
  }

  Future<void> close() async {
    for (final socket in _sockets.toList()) {
      await socket.close();
    }
    await server.close(force: true);
  }
}
