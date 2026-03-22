/// Whether the content is the author's own direct experience or secondhand.
enum PostSourceType {
  /// The author personally witnessed / experienced this event.
  firsthand,

  /// The author is sharing or reporting on someone else's account.
  secondhand,
}

/// Represents a geo-tagged media post (photo or video).
/// GPS coordinates are locked at the moment of capture.
class MediaPost {
  /// Nostr event ID (SHA-256 of serialized event, hex encoded)
  final String id;

  /// Author's Nostr public key hex
  final String pubkey;

  /// SHA-256 hashes of all media files (hex encoded). First entry is primary.
  final List<String> contentHashes;

  /// Absolute local file paths on this device (one per media file).
  final List<String> mediaPaths;

  /// IPFS Content Identifier, set after pinning to IPFS (null if not pinned)
  final String? ipfsCid;

  /// GPS latitude at moment of capture (null if Danger Mode strips GPS)
  final double? latitude;

  /// GPS longitude at moment of capture (null if Danger Mode strips GPS)
  final double? longitude;

  /// Exact timestamp when the camera shutter fired / recording started
  final DateTime capturedAt;

  /// All hashtag event tags this post belongs to (without the '#' prefix).
  /// The first entry is the primary tag used for CivicEvent bucketing.
  final List<String> eventTags;

  /// Whether this was recorded in Danger Mode (face blur + GPS stripped)
  final bool isDangerMode;

  /// Whether the media/text was generated or significantly assisted by AI.
  final bool isAiGenerated;

  /// Whether this is the author's own account or a secondhand report.
  final PostSourceType sourceType;

  /// Whether this post is virtual (game screenshot, artwork, fictional content —
  /// not a real-world event).  GPS is recorded internally but NOT published to
  /// Nostr and NOT shown to other users in the feed.
  final bool isVirtual;

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
    required this.contentHashes,
    this.mediaPaths = const [],
    this.ipfsCid,
    this.latitude,
    this.longitude,
    required this.capturedAt,
    this.eventTags = const [],
    this.isDangerMode = false,
    this.isVirtual = false,
    this.isAiGenerated = false,
    this.sourceType = PostSourceType.firsthand,
    this.caption,
    this.replyToId,
    this.tags = const [],
    required this.nostrEventId,
  });

  // ── Convenience getters ────────────────────────────────────────────────────

  /// Primary event tag (first in [eventTags]), null if none.
  String? get eventTag => eventTags.isEmpty ? null : eventTags.first;

  /// Primary content hash (first in [contentHashes]).
  String get contentHash => contentHashes.first;

  /// Primary local file path (first in [mediaPaths]), null if not cached.
  String? get mediaPath => mediaPaths.isEmpty ? null : mediaPaths.first;

  bool get hasGps => latitude != null && longitude != null;

  // ── Serialisation ──────────────────────────────────────────────────────────

  Map<String, dynamic> toJson() => {
        'id': id,
        'pubkey': pubkey,
        'contentHashes': contentHashes,
        'mediaPaths': mediaPaths,
        'ipfsCid': ipfsCid,
        'latitude': latitude,
        'longitude': longitude,
        'capturedAt': capturedAt.toIso8601String(),
        'eventTags': eventTags,
        'isDangerMode': isDangerMode,
        'isVirtual': isVirtual,
        'isAiGenerated': isAiGenerated,
        'sourceType': sourceType.name,
        'caption': caption,
        'replyToId': replyToId,
        'tags': tags,
        'nostrEventId': nostrEventId,
      };

  factory MediaPost.fromJson(Map<String, dynamic> json) => MediaPost(
        id: json['id'] as String,
        pubkey: json['pubkey'] as String,
        // Support both old single-hash format and new list format
        contentHashes: json['contentHashes'] != null
            ? List<String>.from(json['contentHashes'] as List)
            : [json['contentHash'] as String],
        mediaPaths: json['mediaPaths'] != null
            ? List<String>.from(json['mediaPaths'] as List)
            : (json['mediaPath'] != null ? [json['mediaPath'] as String] : []),
        ipfsCid: json['ipfsCid'] as String?,
        latitude: (json['latitude'] as num?)?.toDouble(),
        longitude: (json['longitude'] as num?)?.toDouble(),
        capturedAt: DateTime.parse(json['capturedAt'] as String),
        // Backward compat: read new list field, fall back to old single string
        eventTags: json['eventTags'] != null
            ? List<String>.from(json['eventTags'] as List)
            : (json['eventTag'] != null ? [json['eventTag'] as String] : []),
        isDangerMode: json['isDangerMode'] as bool? ?? false,
        isVirtual: json['isVirtual'] as bool? ?? false,
        isAiGenerated: json['isAiGenerated'] as bool? ?? false,
        sourceType: _parseSourceType(json['sourceType'] as String?),
        caption: json['caption'] as String?,
        replyToId: json['replyToId'] as String?,
        tags: List<String>.from(json['tags'] as List? ?? []),
        nostrEventId: json['nostrEventId'] as String,
      );

  MediaPost copyWith({
    String? id,
    String? pubkey,
    List<String>? contentHashes,
    List<String>? mediaPaths,
    String? ipfsCid,
    double? latitude,
    double? longitude,
    DateTime? capturedAt,
    List<String>? eventTags,
    bool? isDangerMode,
    String? caption,
    String? replyToId,
    List<String>? tags,
    String? nostrEventId,
    bool? isVirtual,
    bool? isAiGenerated,
    PostSourceType? sourceType,
  }) =>
      MediaPost(
        id: id ?? this.id,
        pubkey: pubkey ?? this.pubkey,
        contentHashes: contentHashes ?? this.contentHashes,
        mediaPaths: mediaPaths ?? this.mediaPaths,
        ipfsCid: ipfsCid ?? this.ipfsCid,
        latitude: latitude ?? this.latitude,
        longitude: longitude ?? this.longitude,
        capturedAt: capturedAt ?? this.capturedAt,
        eventTags: eventTags ?? this.eventTags,
        isDangerMode: isDangerMode ?? this.isDangerMode,
        isVirtual: isVirtual ?? this.isVirtual,
        isAiGenerated: isAiGenerated ?? this.isAiGenerated,
        sourceType: sourceType ?? this.sourceType,
        caption: caption ?? this.caption,
        replyToId: replyToId ?? this.replyToId,
        tags: tags ?? this.tags,
        nostrEventId: nostrEventId ?? this.nostrEventId,
      );

  static PostSourceType _parseSourceType(String? value) =>
      switch (value) {
        'secondhand' => PostSourceType.secondhand,
        _ => PostSourceType.firsthand,
      };

  @override
  String toString() =>
      'MediaPost(id: ${id.substring(0, 8)}..., eventTags: $eventTags, '
      'files: ${contentHashes.length}, isDangerMode: $isDangerMode)';
}
