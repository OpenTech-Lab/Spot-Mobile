/// Represents a geo-tagged media post (photo or video).
/// GPS coordinates are locked at the moment of capture.
class MediaPost {
  /// Nostr event ID (SHA-256 of serialized event, hex encoded)
  final String id;

  /// Author's Nostr public key hex
  final String pubkey;

  /// SHA-256 hash of the raw media file bytes (hex encoded)
  final String contentHash;

  /// Absolute local file path on this device (null if not locally available)
  final String? mediaPath;

  /// IPFS Content Identifier, set after pinning to IPFS (null if not pinned)
  final String? ipfsCid;

  /// GPS latitude at moment of capture (null if Danger Mode strips GPS)
  final double? latitude;

  /// GPS longitude at moment of capture (null if Danger Mode strips GPS)
  final double? longitude;

  /// Exact timestamp when the camera shutter fired / recording started
  final DateTime capturedAt;

  /// Optional event hashtag this post belongs to (without the '#' prefix)
  final String? eventTag;

  /// Whether this was recorded in Danger Mode (face blur + GPS stripped)
  final bool isDangerMode;

  /// Optional text caption added by the author at publish time.
  final String? caption;

  /// Nostr event ID this post is replying to (null if not a reply).
  final String? replyToId;

  /// Arbitrary Nostr tags attached to this post
  final List<String> tags;

  /// The full Nostr event ID for this post (same as [id], kept for clarity)
  final String nostrEventId;

  const MediaPost({
    required this.id,
    required this.pubkey,
    required this.contentHash,
    this.mediaPath,
    this.ipfsCid,
    this.latitude,
    this.longitude,
    required this.capturedAt,
    this.eventTag,
    this.isDangerMode = false,
    this.caption,
    this.replyToId,
    this.tags = const [],
    required this.nostrEventId,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'pubkey': pubkey,
        'contentHash': contentHash,
        'mediaPath': mediaPath,
        'ipfsCid': ipfsCid,
        'latitude': latitude,
        'longitude': longitude,
        'capturedAt': capturedAt.toIso8601String(),
        'eventTag': eventTag,
        'isDangerMode': isDangerMode,
        'caption': caption,
        'replyToId': replyToId,
        'tags': tags,
        'nostrEventId': nostrEventId,
      };

  factory MediaPost.fromJson(Map<String, dynamic> json) => MediaPost(
        id: json['id'] as String,
        pubkey: json['pubkey'] as String,
        contentHash: json['contentHash'] as String,
        mediaPath: json['mediaPath'] as String?,
        ipfsCid: json['ipfsCid'] as String?,
        latitude: (json['latitude'] as num?)?.toDouble(),
        longitude: (json['longitude'] as num?)?.toDouble(),
        capturedAt: DateTime.parse(json['capturedAt'] as String),
        eventTag: json['eventTag'] as String?,
        isDangerMode: json['isDangerMode'] as bool? ?? false,
        caption: json['caption'] as String?,
        replyToId: json['replyToId'] as String?,
        tags: List<String>.from(json['tags'] as List? ?? []),
        nostrEventId: json['nostrEventId'] as String,
      );

  MediaPost copyWith({
    String? id,
    String? pubkey,
    String? contentHash,
    String? mediaPath,
    String? ipfsCid,
    double? latitude,
    double? longitude,
    DateTime? capturedAt,
    String? eventTag,
    bool? isDangerMode,
    String? caption,
    String? replyToId,
    List<String>? tags,
    String? nostrEventId,
  }) =>
      MediaPost(
        id: id ?? this.id,
        pubkey: pubkey ?? this.pubkey,
        contentHash: contentHash ?? this.contentHash,
        mediaPath: mediaPath ?? this.mediaPath,
        ipfsCid: ipfsCid ?? this.ipfsCid,
        latitude: latitude ?? this.latitude,
        longitude: longitude ?? this.longitude,
        capturedAt: capturedAt ?? this.capturedAt,
        eventTag: eventTag ?? this.eventTag,
        isDangerMode: isDangerMode ?? this.isDangerMode,
        caption: caption ?? this.caption,
        replyToId: replyToId ?? this.replyToId,
        tags: tags ?? this.tags,
        nostrEventId: nostrEventId ?? this.nostrEventId,
      );

  bool get hasGps => latitude != null && longitude != null;

  @override
  String toString() =>
      'MediaPost(id: ${id.substring(0, 8)}..., eventTag: $eventTag, isDangerMode: $isDangerMode)';
}
