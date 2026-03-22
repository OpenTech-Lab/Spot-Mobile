import 'dart:convert';

import 'package:mobile/models/media_post.dart';

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

  @override
  String toString() =>
      'NostrEvent(id: ${id.substring(0, 8)}..., kind: $kind, pubkey: ${pubkey.substring(0, 8)}...)';
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

  const CivicEvent({
    required this.hashtag,
    required this.title,
    required this.posts,
    this.centerLat,
    this.centerLon,
    required this.firstSeen,
    required this.participantCount,
  });

  /// Returns the most recent post, or null if there are no posts.
  MediaPost? get latestPost => posts.isEmpty ? null : posts.last;

  /// Returns posts sorted newest-first for feed display.
  List<MediaPost> get postsByNewest =>
      List<MediaPost>.from(posts)..sort((a, b) => b.capturedAt.compareTo(a.capturedAt));

  CivicEvent copyWith({
    String? hashtag,
    String? title,
    List<MediaPost>? posts,
    double? centerLat,
    double? centerLon,
    DateTime? firstSeen,
    int? participantCount,
  }) =>
      CivicEvent(
        hashtag: hashtag ?? this.hashtag,
        title: title ?? this.title,
        posts: posts ?? this.posts,
        centerLat: centerLat ?? this.centerLat,
        centerLon: centerLon ?? this.centerLon,
        firstSeen: firstSeen ?? this.firstSeen,
        participantCount: participantCount ?? this.participantCount,
      );

  @override
  String toString() =>
      'CivicEvent(#$hashtag, posts: ${posts.length}, participants: $participantCount)';
}
