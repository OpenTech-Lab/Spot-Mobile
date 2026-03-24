import 'dart:async';
import 'dart:convert';

import 'package:uuid/uuid.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import 'package:mobile/core/app_config.dart';
import 'package:mobile/core/wallet.dart';
import 'package:mobile/features/nostr/nostr_models.dart';
import 'package:mobile/models/event_model.dart';
import 'package:mobile/models/media_post.dart';
import 'package:mobile/models/wallet_model.dart';

const _relayConnectTimeout = Duration(seconds: 5);
const _publishAckTimeout = Duration(seconds: 8);
/// Relay-indexable single-letter marker used to discover Spot events.
const spotRelayMarkerTag = 'd';

/// Legacy multi-letter marker kept for backward compatibility.
const legacySpotAppTag = 'app';

/// Shared tag value identifying events originating from Spot.
const spotEventOrigin = 'spot';

/// Hidden hashtag marker used for relay discovery on public feeds.
///
/// Public relays reliably index `t` tags, so every Spot event also carries
/// this internal marker to make cross-device feed discovery more reliable.
const spotDiscoveryHashtag = 'spotapp';

/// Nostr event kind for short text / media posts (NIP-01).
const _kindTextNote = 1;

List<List<String>> _spotOriginTags() => const [
  [spotRelayMarkerTag, spotEventOrigin],
  [legacySpotAppTag, spotEventOrigin],
  ['t', spotDiscoveryHashtag],
];

/// Coarsen a coordinate to the nearest 0.5° (~55 km) for privacy.
double _coarseCoord(double v) => (v / 0.5).round() * 0.5;

/// Nostr relay WebSocket client.
///
/// Manages connections to one or more relays and exposes methods to
/// publish events and subscribe to filtered streams.
///
/// Example:
/// ```dart
/// final nostr = NostrService();
/// await nostr.connect();
/// nostr.publishEvent(event);
/// final sub = nostr.subscribe([NostrFilter(kinds: [1], limit: 20)], (e) { ... });
/// ```
class NostrService {
  NostrService({List<String>? relayUrls})
    : _relayUrls = relayUrls ?? AppConfig.relays;

  final List<String> _relayUrls;
  final _uuid = const Uuid();

  /// Active WebSocket channels keyed by relay URL.
  final Map<String, WebSocketChannel> _channels = {};

  /// In-flight connection attempts keyed by relay URL.
  final Map<String, Future<void>> _connecting = {};

  /// Active subscriptions keyed by subscription ID.
  final Map<String, _SubscriptionState> _subscriptions = {};

  /// Pending publish acknowledgements keyed by event ID.
  final Map<String, _PendingPublish> _pendingPublishes = {};

  /// Broadcast stream controller for all inbound relay messages.
  final _inbound = StreamController<_RelayMessage>.broadcast();

  // ── Connection management ─────────────────────────────────────────────────

  /// Connects to all configured relays.
  Future<void> connect([List<String>? relayUrls]) async {
    final urls = relayUrls ?? _relayUrls;
    await Future.wait(urls.map(_connectRelay));
  }

  Future<void> _connectRelay(String url) {
    if (_channels.containsKey(url)) return Future.value();
    final existing = _connecting[url];
    if (existing != null) return existing;

    final attempt = _openRelay(url).whenComplete(() {
      _connecting.remove(url);
    });
    _connecting[url] = attempt;
    return attempt;
  }

  Future<void> _openRelay(String url) async {
    try {
      final channel = WebSocketChannel.connect(Uri.parse(url));

      channel.stream.listen(
        (raw) => _handleIncoming(url, raw),
        onError: (error) {
          _channels.remove(url);
          _markRelayPublishFailure(url, 'socket error: $error');
        },
        onDone: () {
          _channels.remove(url);
          _markRelayPublishFailure(url, 'connection closed');
        },
      );

      await channel.ready.timeout(_relayConnectTimeout);
      _channels[url] = channel;

      // Re-subscribe on reconnect
      for (final sub in _subscriptions.values) {
        _sendReq(channel, sub.id, sub.filters);
      }
    } catch (_) {
      // Silently ignore unreachable relays; the app degrades gracefully.
    }
  }

  /// Disconnects from all relays and cancels all subscriptions.
  Future<void> disconnect() async {
    final channels = _channels.values.toList(growable: false);
    for (final channel in channels) {
      await channel.sink.close();
    }
    _channels.clear();
    _subscriptions.clear();
    await _inbound.close();
  }

  // ── Publishing ────────────────────────────────────────────────────────────

  /// Broadcasts [event] to all connected relays.
  Future<void> publishEvent(NostrEvent event) async {
    // Purge stale channels so connect() re-establishes them.
    _channels.removeWhere((url, channel) => channel.closeCode != null);
    await connect();
    if (_channels.isEmpty) {
      throw StateError('No connected relays available');
    }

    final relayUrls = _channels.keys.toList(growable: false);
    final pending = _PendingPublish(eventId: event.id, relayUrls: relayUrls);
    _pendingPublishes[event.id] = pending;

    final msg = jsonEncode(['EVENT', event.toJson()]);
    for (final channel in _channels.values.toList(growable: false)) {
      channel.sink.add(msg);
    }
    final verifySubId = subscribe([
      NostrFilter(ids: [event.id], limit: 1),
    ], (_) {});

    try {
      await pending.waitForAcceptance(_publishAckTimeout);
    } finally {
      unsubscribe(verifySubId);
      _pendingPublishes.remove(event.id);
    }
  }

  /// Builds and publishes a Nostr kind-1 event for [post].
  /// Returns the signed [NostrEvent] that was broadcast.
  Future<NostrEvent> publishMediaPost(
    MediaPost post,
    WalletModel wallet,
  ) async {
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;

    // Build content: optional caption + optional #tag lines
    final contentParts = <String>[];
    if (post.caption?.isNotEmpty == true) contentParts.add(post.caption!);
    for (final t in post.eventTags) {
      contentParts.add('#$t');
    }
    String content = contentParts.join('\n');
    if (content.isEmpty) {
      // Some Nostr relays reject kind-1 events with completely empty content.
      // Provide a minimal fallback for image-only posts.
      content = ' ';
    }

    final signed = _signMediaPostEvent(
      post,
      wallet,
      now: now,
      content: content,
    );

    await publishEvent(signed);

    // Self-deliver immediately so the post appears in the feed without
    // waiting for a relay echo (many relays delay or filter kind-1 events).
    for (final sub in _subscriptions.values) {
      sub.onEvent(signed);
    }

    return signed;
  }

  NostrEvent _signMediaPostEvent(
    MediaPost post,
    WalletModel wallet, {
    required int now,
    required String content,
  }) {
    final tags = <List<String>>[
      ..._spotOriginTags(),
      if (post.replyToId != null) ['e', post.replyToId!, '', 'reply'],
      for (final t in post.eventTags) ['t', t],
      // Virtual posts: GPS is recorded locally but NOT published to Nostr.
      // Spot check-in: publish exact GPS + spot tag.
      // Default: always coarsen GPS to ~0.5° (~55 km).
      if (!post.isVirtual &&
          post.latitude != null &&
          post.longitude != null) ...[
        if (post.isSpotCheckIn) ...[
          ['geo', post.latitude.toString(), post.longitude.toString()],
          ['spot', post.spotName!],
        ] else ...[
          [
            'geo',
            _coarseCoord(post.latitude!).toString(),
            _coarseCoord(post.longitude!).toString(),
          ],
        ],
      ],
      if (!post.isTextOnly)
        for (final hash in post.contentHashes) ['media_hash', hash],
      if (post.ipfsCid != null) ['ipfs', post.ipfsCid!],
      if (post.isDangerMode) ['danger', '1'],
      if (post.isVirtual) ['virtual', '1'],
      if (post.isAiGenerated) ['ai_content', '1'],
      if (post.isTextOnly) ['text_only', '1'],
      ['source', post.sourceType.name],
    ];
    final placeholder = NostrEvent(
      id: '',
      pubkey: wallet.publicKeyHex,
      createdAt: now,
      kind: _kindTextNote,
      tags: tags,
      content: content,
      sig: '',
    );

    final id = WalletService.computeEventId(placeholder);
    final withId = NostrEvent(
      id: id,
      pubkey: placeholder.pubkey,
      createdAt: placeholder.createdAt,
      kind: placeholder.kind,
      tags: placeholder.tags,
      content: placeholder.content,
      sig: '',
    );

    final sig = WalletService.signNostrEvent(withId, wallet.privateKeyHex);
    return NostrEvent(
      id: withId.id,
      pubkey: withId.pubkey,
      createdAt: withId.createdAt,
      kind: withId.kind,
      tags: withId.tags,
      content: withId.content,
      sig: sig,
    );
  }

  /// Publishes a witness signal (seen / confirm / deny) for an event hashtag.
  ///
  /// Witness events are kind-1 events with a `witness` tag carrying the
  /// signal type. They are Spot-tagged and optionally carry a GPS location.
  Future<NostrEvent> publishWitness({
    required String hashtag,
    required String witnessType, // 'seen' | 'confirm' | 'deny'
    required WalletModel wallet,
    double? lat,
    double? lon,
  }) async {
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;

    final tags = <List<String>>[
      ..._spotOriginTags(),
      ['t', hashtag],
      ['witness', witnessType],
      if (lat != null && lon != null) ['geo', lat.toString(), lon.toString()],
    ];

    final placeholder = NostrEvent(
      id: '',
      pubkey: wallet.publicKeyHex,
      createdAt: now,
      kind: _kindTextNote,
      tags: tags,
      content: witnessType,
      sig: '',
    );

    final id = WalletService.computeEventId(placeholder);
    final withId = NostrEvent(
      id: id,
      pubkey: placeholder.pubkey,
      createdAt: placeholder.createdAt,
      kind: placeholder.kind,
      tags: placeholder.tags,
      content: placeholder.content,
      sig: '',
    );

    final sig = WalletService.signNostrEvent(withId, wallet.privateKeyHex);
    final signed = NostrEvent(
      id: withId.id,
      pubkey: withId.pubkey,
      createdAt: withId.createdAt,
      kind: withId.kind,
      tags: withId.tags,
      content: withId.content,
      sig: sig,
    );

    await publishEvent(signed);

    // Self-deliver
    for (final sub in _subscriptions.values) {
      sub.onEvent(signed);
    }

    return signed;
  }

  /// Publishes a NIP-09 kind-5 revocation event for [eventId].
  ///
  /// Spec v1.4 §12 "Deletion Flow" step 1: include the content hash so that
  /// compliant clients can block by hash in addition to event ID.
  Future<void> deletePost(
    String eventId,
    String contentHash,
    WalletModel wallet,
  ) async {
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;

    final tags = <List<String>>[
      ..._spotOriginTags(),
      ['e', eventId],
      ['media_hash', contentHash], // hash-based revocation (spec v1.4 §12)
    ];

    final placeholder = NostrEvent(
      id: '',
      pubkey: wallet.publicKeyHex,
      createdAt: now,
      kind: 5, // NIP-09 deletion
      tags: tags,
      content: '',
      sig: '',
    );

    final id = WalletService.computeEventId(placeholder);
    final withId = NostrEvent(
      id: id,
      pubkey: placeholder.pubkey,
      createdAt: placeholder.createdAt,
      kind: placeholder.kind,
      tags: placeholder.tags,
      content: placeholder.content,
      sig: '',
    );

    final sig = WalletService.signNostrEvent(withId, wallet.privateKeyHex);
    final signed = NostrEvent(
      id: withId.id,
      pubkey: withId.pubkey,
      createdAt: withId.createdAt,
      kind: withId.kind,
      tags: withId.tags,
      content: withId.content,
      sig: sig,
    );

    await publishEvent(signed);
  }

  /// Publishes a NIP-56 kind-1984 report event.
  ///
  /// Spec v1.4 §12.B: users can report content → blocklist propagates across
  /// the network. All compliant clients suppress reported content from feeds.
  Future<void> reportContent({
    required String eventId,
    required String contentHash,
    required String reason,
    required WalletModel wallet,
  }) async {
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;

    final tags = <List<String>>[
      ..._spotOriginTags(),
      ['e', eventId, reason],
      ['media_hash', contentHash],
    ];

    final placeholder = NostrEvent(
      id: '',
      pubkey: wallet.publicKeyHex,
      createdAt: now,
      kind: 1984, // NIP-56 reporting
      tags: tags,
      content: reason,
      sig: '',
    );

    final id = WalletService.computeEventId(placeholder);
    final withId = NostrEvent(
      id: id,
      pubkey: placeholder.pubkey,
      createdAt: placeholder.createdAt,
      kind: placeholder.kind,
      tags: placeholder.tags,
      content: placeholder.content,
      sig: '',
    );

    final sig = WalletService.signNostrEvent(withId, wallet.privateKeyHex);
    final signed = NostrEvent(
      id: withId.id,
      pubkey: withId.pubkey,
      createdAt: withId.createdAt,
      kind: withId.kind,
      tags: withId.tags,
      content: withId.content,
      sig: sig,
    );

    await publishEvent(signed);
  }

  // ── Subscriptions ─────────────────────────────────────────────────────────

  /// Subscribes to events matching [filters] and delivers them to [onEvent].
  /// Returns the subscription ID (use with [unsubscribe]).
  String subscribe(
    List<NostrFilter> filters,
    void Function(NostrEvent) onEvent,
  ) {
    final id = _uuid.v4();
    _subscriptions[id] = _SubscriptionState(
      id: id,
      filters: filters,
      onEvent: onEvent,
    );

    for (final channel in _channels.values) {
      _sendReq(channel, id, filters);
    }

    return id;
  }

  /// Cancels the subscription with [subscriptionId].
  void unsubscribe(String subscriptionId) {
    _subscriptions.remove(subscriptionId);
    final msg = jsonEncode(['CLOSE', subscriptionId]);
    for (final channel in _channels.values) {
      channel.sink.add(msg);
    }
  }

  /// Returns a stream of [NostrEvent]s matching the given [hashtag] tag.
  Stream<NostrEvent> fetchEventsByTag(String hashtag) {
    final controller = StreamController<NostrEvent>.broadcast();

    final filters = [
      NostrFilter(
        kinds: [_kindTextNote],
        limit: 100,
        tags: {
          't': [hashtag],
        },
      ),
    ];

    String? subId;
    subId = subscribe(filters, (event) {
      if (!controller.isClosed) controller.add(event);
    });

    controller.onCancel = () {
      if (subId != null) unsubscribe(subId);
    };

    return controller.stream;
  }

  // ── Internal ──────────────────────────────────────────────────────────────

  void _sendReq(
    WebSocketChannel channel,
    String id,
    List<NostrFilter> filters,
  ) {
    final msg = jsonEncode(['REQ', id, ...filters.map((f) => f.toJson())]);
    channel.sink.add(msg);
  }

  void _handleIncoming(String relayUrl, dynamic raw) {
    try {
      final data = jsonDecode(raw as String) as List;
      if (data.isEmpty) return;

      final type = data[0] as String;

      switch (type) {
        case 'EVENT':
          if (data.length < 3) return;
          final subId = data[1] as String;
          final eventJson = data[2] as Map<String, dynamic>;
          final event = NostrEvent.fromJson(eventJson);
          _pendingPublishes[event.id]?.record(
            relayUrl,
            accepted: true,
            message: 'relay echoed stored event',
          );
          _subscriptions[subId]?.onEvent(event);
          _inbound.add(_RelayMessage(relayUrl: relayUrl, event: event));

        case 'OK':
          if (data.length < 4) return;
          final eventId = data[1] as String;
          final accepted = data[2] == true;
          final message = data[3]?.toString() ?? '';
          _pendingPublishes[eventId]?.record(
            relayUrl,
            accepted: accepted,
            message: message,
          );

        case 'NOTICE':
          // Relay notice — log but do not surface to app layer.
          break;

        case 'EOSE':
          // End of stored events — could notify subscribers if needed.
          break;

        default:
          break;
      }
    } catch (_) {
      // Malformed message from relay — ignore.
    }
  }

  /// All configured relay URLs (regardless of connection state).
  List<String> get relayUrls => List.unmodifiable(_relayUrls);

  /// List of currently connected relay URLs.
  List<String> get connectedRelays => List.unmodifiable(_channels.keys);

  void _markRelayPublishFailure(String relayUrl, String reason) {
    for (final publish in _pendingPublishes.values) {
      publish.record(relayUrl, accepted: false, message: reason);
    }
  }

}

// ── Private helpers ───────────────────────────────────────────────────────

class _SubscriptionState {
  final String id;
  final List<NostrFilter> filters;
  final void Function(NostrEvent) onEvent;

  const _SubscriptionState({
    required this.id,
    required this.filters,
    required this.onEvent,
  });
}

class _RelayMessage {
  final String relayUrl;
  final NostrEvent event;

  const _RelayMessage({required this.relayUrl, required this.event});
}

class _PendingPublish {
  _PendingPublish({required this.eventId, required List<String> relayUrls})
    : _expectedRelays = relayUrls.toSet();

  final String eventId;
  final Set<String> _expectedRelays;
  final Map<String, ({bool accepted, String message})> _responses = {};
  final Completer<void> _completer = Completer<void>();

  void record(
    String relayUrl, {
    required bool accepted,
    required String message,
  }) {
    if (!_expectedRelays.contains(relayUrl) ||
        _responses.containsKey(relayUrl)) {
      return;
    }

    _responses[relayUrl] = (accepted: accepted, message: message);

    if (accepted) {
      if (!_completer.isCompleted) {
        _completer.complete();
      }
      return;
    }

    if (_responses.length == _expectedRelays.length &&
        !_completer.isCompleted) {
      _completer.completeError(StateError(_failureSummary()));
    }
  }

  Future<void> waitForAcceptance(Duration timeout) async {
    try {
      await _completer.future.timeout(timeout);
    } on TimeoutException {
      throw StateError(_failureSummary(timedOut: true));
    }
  }

  String _failureSummary({bool timedOut = false}) {
    final rejected = _responses.entries
        .where((entry) => !entry.value.accepted)
        .map((entry) {
          final suffix = entry.value.message.isEmpty
              ? ''
              : ' (${entry.value.message})';
          return '${entry.key}$suffix';
        })
        .toList(growable: false);
    final missing = _expectedRelays.difference(_responses.keys.toSet()).toList()
      ..sort();

    final parts = <String>['No relay accepted Nostr event $eventId'];
    if (rejected.isNotEmpty) {
      parts.add('rejected by ${rejected.join(', ')}');
    }
    if (missing.isNotEmpty) {
      parts.add(
        timedOut
            ? 'timed out waiting for ${missing.join(', ')}'
            : 'no response from ${missing.join(', ')}',
      );
    }
    return parts.join('; ');
  }
}
