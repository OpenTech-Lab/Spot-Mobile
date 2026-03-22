import 'package:mobile/models/media_post.dart';

/// Evidence integrity / trust metadata computed from a [MediaPost].
///
/// Evidence is not stored separately on Nostr — it is derived by running
/// [TrustService] over an existing [MediaPost].  This class is a value object
/// that travels alongside its source post inside [CivicEvent].
class Evidence {
  /// Matches [MediaPost.id].
  final String id;

  /// The [CivicEvent] hashtag this evidence belongs to.
  final String eventId;

  /// Author's Nostr pubkey.
  final String uploaderId;

  /// Primary SHA-256 content hash (first in [MediaPost.contentHashes]).
  final String mediaHash;

  /// 'image' | 'video' | 'unknown'
  final String mediaType;

  /// When the media was captured (device clock).
  final DateTime claimedTime;

  /// GPS latitude claimed by the uploader (null if Danger Mode).
  final double? claimedLat;

  /// GPS longitude claimed by the uploader (null if Danger Mode).
  final double? claimedLon;

  /// Data-integrity score 0.0–1.0: hash uniqueness, metadata consistency.
  final double integrityScore;

  /// Composite EBES trust score 0.0–1.0.
  final double trustScore;

  const Evidence({
    required this.id,
    required this.eventId,
    required this.uploaderId,
    required this.mediaHash,
    required this.mediaType,
    required this.claimedTime,
    this.claimedLat,
    this.claimedLon,
    required this.integrityScore,
    required this.trustScore,
  });

  /// Derives an [Evidence] from a [MediaPost] with pre-computed scores.
  factory Evidence.fromMediaPost(
    MediaPost post, {
    required String eventId,
    required double integrityScore,
    required double trustScore,
  }) =>
      Evidence(
        id: post.id,
        eventId: eventId,
        uploaderId: post.pubkey,
        mediaHash: post.contentHash,
        mediaType: _inferMediaType(post.mediaPath),
        claimedTime: post.capturedAt,
        claimedLat: post.latitude,
        claimedLon: post.longitude,
        integrityScore: integrityScore,
        trustScore: trustScore,
      );

  /// Human-readable confidence label.
  String get confidenceLabel {
    if (trustScore >= 0.7) return 'Verified';
    if (trustScore >= 0.4) return 'Unverified';
    return 'Suspicious';
  }

  static String _inferMediaType(String? path) {
    if (path == null) return 'unknown';
    final lower = path.toLowerCase();
    if (lower.endsWith('.mp4') ||
        lower.endsWith('.mov') ||
        lower.endsWith('.avi') ||
        lower.endsWith('.mkv')) {
      return 'video';
    }
    return 'image';
  }
}
