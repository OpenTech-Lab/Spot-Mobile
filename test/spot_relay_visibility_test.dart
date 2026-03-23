import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

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
      expect(event.getAllTagValues('t'), ['tokyo']);
      expect(event.content, contains('Test post'));
      await service.disconnect();
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

    test('connect only reports relays after websocket readiness', () async {
      acceptedRelay = await _TestRelay.start(name: 'accepted');
      rejectedRelay = await _TestRelay.start(name: 'rejected');

      final service = NostrService(
        relayUrls: [acceptedRelay!.url, rejectedRelay!.url],
      );

      final connectFuture = service.connect();
      expect(service.connectedRelays, isEmpty);

      await connectFuture;

      expect(
        service.connectedRelays.toSet(),
        {acceptedRelay!.url, rejectedRelay!.url},
      );
      await service.disconnect();
    });

    test('publishMediaPost succeeds when at least one relay accepts', () async {
      acceptedRelay = await _TestRelay.start(name: 'accepted', acceptEvents: true);
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
