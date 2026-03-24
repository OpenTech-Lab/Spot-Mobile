// Nostr protocol type definitions.
// See https://github.com/nostr-protocol/nostr for the full specification.

// ── Filter ────────────────────────────────────────────────────────────────

/// A Nostr subscription filter.  Null fields are omitted from the JSON
/// to avoid sending unnecessary constraints to the relay.
class NostrFilter {
  final List<String>? ids;
  final List<int>? kinds;
  final List<String>? authors;
  final int? since;
  final int? until;
  final int? limit;

  /// Tag filters, e.g. {'t': ['protest', 'demo']}
  final Map<String, List<String>>? tags;

  const NostrFilter({
    this.ids,
    this.kinds,
    this.authors,
    this.since,
    this.until,
    this.limit,
    this.tags,
  });

  Map<String, dynamic> toJson() {
    final m = <String, dynamic>{};
    if (ids != null) m['ids'] = ids;
    if (kinds != null) m['kinds'] = kinds;
    if (authors != null) m['authors'] = authors;
    if (since != null) m['since'] = since;
    if (until != null) m['until'] = until;
    if (limit != null) m['limit'] = limit;
    if (tags != null) {
      for (final entry in tags!.entries) {
        m['#${entry.key}'] = entry.value;
      }
    }
    return m;
  }
}

// ── Subscription ─────────────────────────────────────────────────────────

/// An active Nostr subscription with its filters.
class NostrSubscription {
  final String id;
  final List<NostrFilter> filters;

  const NostrSubscription({required this.id, required this.filters});
}

// ── Relay ─────────────────────────────────────────────────────────────────

/// Represents a Nostr relay connection.
class NostrRelay {
  final String url;
  final bool isConnected;

  const NostrRelay({required this.url, required this.isConnected});

  NostrRelay copyWith({String? url, bool? isConnected}) => NostrRelay(
    url: url ?? this.url,
    isConnected: isConnected ?? this.isConnected,
  );

  @override
  String toString() => 'NostrRelay($url, connected: $isConnected)';
}

// ── Message types ─────────────────────────────────────────────────────────

/// Incoming/outgoing message types on the Nostr WebSocket protocol.
enum NostrMessageType {
  /// Client → Relay: subscribe with filters
  req,

  /// Relay → Client: matching event
  event,

  /// Client → Relay: unsubscribe
  close,

  /// Relay → Client: human-readable notice
  notice,

  /// Relay → Client: end of stored events for a subscription
  eose,

  /// Client → Relay: publish a new event
  publish,
}

/// A message sent or received over the Nostr WebSocket.
class NostrMessage {
  final NostrMessageType type;
  final dynamic payload;

  const NostrMessage({required this.type, required this.payload});

  @override
  String toString() => 'NostrMessage(type: $type, payload: $payload)';
}
