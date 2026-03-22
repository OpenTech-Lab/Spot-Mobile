import 'dart:async';
import 'dart:convert';

import 'package:uuid/uuid.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import 'package:mobile/core/wallet.dart';
import 'package:mobile/features/nostr/nostr_models.dart';
import 'package:mobile/models/event_model.dart';
import 'package:mobile/models/media_post.dart';
import 'package:mobile/models/wallet_model.dart';

/// Default public Nostr relays used when none are specified.
const _defaultRelays = [
  'wss://relay.damus.io',
  'wss://nos.lol',
  'wss://relay.nostr.band',
];

/// Nostr event kind for short text / media posts (NIP-01).
const _kindTextNote = 1;

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
      : _relayUrls = relayUrls ?? _defaultRelays;

  final List<String> _relayUrls;
  final _uuid = const Uuid();

  /// Active WebSocket channels keyed by relay URL.
  final Map<String, WebSocketChannel> _channels = {};

  /// Active subscriptions keyed by subscription ID.
  final Map<String, _SubscriptionState> _subscriptions = {};

  /// Broadcast stream controller for all inbound relay messages.
  final _inbound = StreamController<_RelayMessage>.broadcast();

  // ── Connection management ─────────────────────────────────────────────────

  /// Connects to all configured relays.
  Future<void> connect([List<String>? relayUrls]) async {
    final urls = relayUrls ?? _relayUrls;
    for (final url in urls) {
      _connectRelay(url);
    }
  }

  void _connectRelay(String url) {
    if (_channels.containsKey(url)) return;
    try {
      final channel = WebSocketChannel.connect(Uri.parse(url));
      _channels[url] = channel;

      channel.stream.listen(
        (raw) => _handleIncoming(url, raw),
        onError: (_) => _channels.remove(url),
        onDone: () => _channels.remove(url),
      );

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
    for (final channel in _channels.values) {
      await channel.sink.close();
    }
    _channels.clear();
    _subscriptions.clear();
    await _inbound.close();
  }

  // ── Publishing ────────────────────────────────────────────────────────────

  /// Broadcasts [event] to all connected relays.
  void publishEvent(NostrEvent event) {
    final msg = jsonEncode(['EVENT', event.toJson()]);
    for (final channel in _channels.values) {
      channel.sink.add(msg);
    }
  }

  /// Builds and publishes a Nostr kind-1 event for [post].
  /// Returns the signed [NostrEvent] that was broadcast.
  Future<NostrEvent> publishMediaPost(
      MediaPost post, WalletModel wallet) async {
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;

    // Build content: optional caption + optional #tag
    final contentParts = <String>[];
    if (post.caption?.isNotEmpty == true) contentParts.add(post.caption!);
    if (post.eventTag != null) contentParts.add('#${post.eventTag}');
    final content = contentParts.join('\n');

    final tags = <List<String>>[
      ['app', 'spot'], // identifies events originating from the Spot app
      if (post.replyToId != null) ['e', post.replyToId!, '', 'reply'],
      if (post.eventTag != null) ['t', post.eventTag!],
      if (post.latitude != null && post.longitude != null)
        ['geo', post.latitude.toString(), post.longitude.toString()],
      ['media_hash', post.contentHash],
      if (post.ipfsCid != null) ['ipfs', post.ipfsCid!],
      if (post.isDangerMode) ['danger', '1'],
    ];

    // Build a placeholder event to compute its ID
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

    final signed = NostrEvent(
      id: withId.id,
      pubkey: withId.pubkey,
      createdAt: withId.createdAt,
      kind: withId.kind,
      tags: withId.tags,
      content: withId.content,
      sig: sig,
    );

    publishEvent(signed);
    return signed;
  }

  // ── Subscriptions ─────────────────────────────────────────────────────────

  /// Subscribes to events matching [filters] and delivers them to [onEvent].
  /// Returns the subscription ID (use with [unsubscribe]).
  String subscribe(List<NostrFilter> filters, void Function(NostrEvent) onEvent) {
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
      WebSocketChannel channel, String id, List<NostrFilter> filters) {
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
          _subscriptions[subId]?.onEvent(event);
          _inbound.add(_RelayMessage(relayUrl: relayUrl, event: event));

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

  /// List of currently connected relay URLs.
  List<String> get connectedRelays => List.unmodifiable(_channels.keys);
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
