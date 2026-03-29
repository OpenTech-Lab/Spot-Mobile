import 'dart:convert';

import 'package:mobile/models/media_post.dart';
import 'package:mobile/models/witness_model.dart';

/// NIP-01 Nostr event.
/// The event ID is the SHA-256 of the canonical serialisation defined by Nostr.
class NostrEvent {
  /// SHA-256 of the serialized event (hex encoded)
  final String id;

  /// Author public key (hex encoded, 32 bytes / 64 hex chars)
  final String pubkey;

  /// Unix timestamp (seconds since epoch)
  final int createdAt;

  /// Nostr event kind (1 = short text / media post, 30000+ = parameterized replaceable)
  final int kind;

  /// Nostr tags e.g. [["t", "hashtag"], ["geo", "lat", "lon"]]
  final List<List<String>> tags;

  /// Event content (plaintext or JSON depending on kind)
  final String content;

  /// ECDSA / Schnorr signature over the event ID (hex encoded)
  final String sig;

  const NostrEvent({
    required this.id,
    required this.pubkey,
    required this.createdAt,
    required this.kind,
    required this.tags,
    required this.content,
    required this.sig,
  });

  /// Returns the canonical JSON array used to compute the event ID.
  /// Format: [0, pubkey, created_at, kind, tags, content]
  String serialize() => jsonEncode([0, pubkey, createdAt, kind, tags, content]);

  Map<String, dynamic> toJson() => {
    'id': id,
    'pubkey': pubkey,
    'created_at': createdAt,
    'kind': kind,
    'tags': tags,
    'content': content,
    'sig': sig,
  };

  factory NostrEvent.fromJson(Map<String, dynamic> json) => NostrEvent(
    id: json['id'] as String,
    pubkey: json['pubkey'] as String,
    createdAt: json['created_at'] as int,
    kind: json['kind'] as int,
    tags: (json['tags'] as List)
        .map((t) => List<String>.from(t as List))
        .toList(),
    content: json['content'] as String,
    sig: json['sig'] as String,
  );

  /// Convenience getter: find the first value for a given tag name.
  String? getTagValue(String name) {
    for (final tag in tags) {
      if (tag.isNotEmpty && tag[0] == name && tag.length > 1) {
        return tag[1];
      }
    }
    return null;
  }

  /// Returns all values for a given tag name (e.g. multiple media_hash tags).
  List<String> getAllTagValues(String name) {
    final result = <String>[];
    for (final tag in tags) {
      if (tag.isNotEmpty && tag[0] == name && tag.length > 1) {
        result.add(tag[1]);
      }
    }
    return result;
  }

  @override
  String toString() =>
      'NostrEvent(id: ${id.substring(0, 8)}..., kind: $kind, pubkey: ${pubkey.substring(0, 8)}...)';
}

/// EBES confidence status for a [CivicEvent].
enum EventStatus {
  /// Not enough evidence to draw a conclusion.
  unverified,

  /// Multiple independent sources confirm the event; trust score ≥ 0.65.
  highConfidence,

  /// Significant deny-witness signals detected; likely disputed or fake.
  conflicted,
}

/// App-level grouping of [MediaPost]s under a shared event hashtag.
/// Conceptually similar to a live Wikipedia page with timeline and map.
class CivicEvent {
  /// The hashtag (without '#') that identifies this event across all posts.
  final String hashtag;

  /// Human-readable title derived from the hashtag or first post description.
  final String title;

  /// All media posts associated with this hashtag, sorted oldest-first.
  final List<MediaPost> posts;

  /// Approximate geographic centre of all posts (null if GPS stripped).
  final double? centerLat;
  final double? centerLon;

  /// Timestamp of the earliest post for this event.
  final DateTime firstSeen;

  /// Number of unique pubkeys that have contributed posts.
  final int participantCount;

  // ── EBES fields ────────────────────────────────────────────────────────────

  /// Aggregate EBES trust score 0.0–1.0 computed by [TrustService].
  final double trustScore;

  /// Human-readable confidence level derived from [trustScore] + [witnesses].
  final EventStatus status;

  /// Witness signals (seen / confirm / deny) received for this event.
  final List<Witness> witnesses;

  const CivicEvent({
    required this.hashtag,
    required this.title,
    required this.posts,
    this.centerLat,
    this.centerLon,
    required this.firstSeen,
    required this.participantCount,
    this.trustScore = 0.0,
    this.status = EventStatus.unverified,
    this.witnesses = const [],
  });

  /// Returns the most recent post, or null if there are no posts.
  MediaPost? get latestPost => posts.isEmpty ? null : posts.last;

  /// Returns the most recent non-reply post in this event, if any.
  DateTime? get lastPostAt =>
      _latestCapturedAtWhere((post) => post.replyToId == null);

  /// Returns the most recent reply in this event, if any.
  DateTime? get lastReplyAt =>
      _latestCapturedAtWhere((post) => post.replyToId != null);

  /// Returns the newest visible activity for this event.
  DateTime get lastActivityAt {
    final postAt = lastPostAt;
    final replyAt = lastReplyAt;
    if (postAt == null) return replyAt ?? firstSeen;
    if (replyAt == null) return postAt;
    return replyAt.isAfter(postAt) ? replyAt : postAt;
  }

  /// Returns posts sorted newest-first for feed display.
  List<MediaPost> get postsByNewest =>
      List<MediaPost>.from(posts)
        ..sort((a, b) => b.capturedAt.compareTo(a.capturedAt));

  DateTime? _latestCapturedAtWhere(bool Function(MediaPost post) predicate) {
    DateTime? latest;
    for (final post in posts) {
      if (!predicate(post)) continue;
      if (latest == null || post.capturedAt.isAfter(latest)) {
        latest = post.capturedAt;
      }
    }
    return latest;
  }

  // ── EBES convenience getters ───────────────────────────────────────────────

  /// Percentage representation of [trustScore] (0–100).
  int get trustPercent => (trustScore * 100).round();

  /// Counts of each witness type.
  int get seenCount =>
      witnesses.where((w) => w.type == WitnessType.seen).length;
  int get confirmCount =>
      witnesses.where((w) => w.type == WitnessType.confirm).length;
  int get denyCount =>
      witnesses.where((w) => w.type == WitnessType.deny).length;

  CivicEvent copyWith({
    String? hashtag,
    String? title,
    List<MediaPost>? posts,
    double? centerLat,
    double? centerLon,
    DateTime? firstSeen,
    int? participantCount,
    double? trustScore,
    EventStatus? status,
    List<Witness>? witnesses,
  }) => CivicEvent(
    hashtag: hashtag ?? this.hashtag,
    title: title ?? this.title,
    posts: posts ?? this.posts,
    centerLat: centerLat ?? this.centerLat,
    centerLon: centerLon ?? this.centerLon,
    firstSeen: firstSeen ?? this.firstSeen,
    participantCount: participantCount ?? this.participantCount,
    trustScore: trustScore ?? this.trustScore,
    status: status ?? this.status,
    witnesses: witnesses ?? this.witnesses,
  );

  @override
  String toString() =>
      'CivicEvent(#$hashtag, posts: ${posts.length}, participants: $participantCount)';
}
