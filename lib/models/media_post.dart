/// Whether the content is the author's own direct experience or secondhand.
enum PostSourceType {
  /// The author personally witnessed / experienced this event.
  firsthand,

  /// The author is sharing or reporting on someone else's account.
  secondhand,
}

enum PostDeliveryState { sent, failedToSend }

/// Represents a geo-tagged media post (photo or video).
/// GPS coordinates are locked at the moment of capture.
class MediaPost {
  /// Nostr event ID (SHA-256 of serialized event, hex encoded)
  final String id;

  /// Author's Nostr public key hex
  final String pubkey;

  /// Latest visible profile name for this author, if known.
  final String? authorDisplayName;

  /// Latest visible avatar content hash for this author, if known.
  final String? authorAvatarContentHash;

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

  /// Whether this post is text-only and carries no downloadable media.
  final bool isTextOnly;

  /// Optional inline preview image for remote rendering when raw media has not
  /// been synced yet.
  final String? previewBase64;
  final String? previewMimeType;

  /// Whether this is the author's own account or a secondhand report.
  final PostSourceType sourceType;

  /// Whether this post is virtual (game screenshot, artwork, fictional content —
  /// not a real-world event).  GPS is recorded internally but NOT published to
  /// Nostr and NOT shown to other users in the feed.
  final bool isVirtual;

  /// User-provided place name for a Spot check-in (e.g. "Eiffel Tower").
  /// When non-null and non-empty, exact GPS is published instead of coarsened.
  final String? spotName;

  /// Frozen location text shown to the user when this post was composed.
  ///
  /// This keeps normal privacy-rounded posts from drifting to a nearby city
  /// when later UI surfaces reverse-geocode the rounded coordinate pair.
  final String? visibleLocationLabel;

  /// Number of replies to this post (computed at display time).
  final int replyCount;

  /// Number of likes / reactions on this post (computed at display time).
  final int likeCount;

  /// Whether the local device has liked this post.
  final bool isLikedByMe;

  /// Optional text caption added by the author at publish time.
  final String? caption;

  /// Nostr event ID this post is replying to (null if not a reply).
  final String? replyToId;

  /// Arbitrary Nostr tags attached to this post
  final List<String> tags;

  /// The full Nostr event ID for this post (same as [id], kept for clarity)
  final String nostrEventId;

  /// Whether this post was published remotely or is still only stored locally.
  final PostDeliveryState deliveryState;

  /// Last publish error shown to the local author for retryable failures.
  final String? lastPublishError;

  const MediaPost({
    required this.id,
    required this.pubkey,
    this.authorDisplayName,
    this.authorAvatarContentHash,
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
    this.isTextOnly = false,
    this.previewBase64,
    this.previewMimeType,
    this.sourceType = PostSourceType.firsthand,
    this.caption,
    this.replyToId,
    this.tags = const [],
    required this.nostrEventId,
    this.spotName,
    this.visibleLocationLabel,
    this.replyCount = 0,
    this.likeCount = 0,
    this.isLikedByMe = false,
    this.deliveryState = PostDeliveryState.sent,
    this.lastPublishError,
  });

  static const Object _copyWithUnset = Object();

  // ── Convenience getters ────────────────────────────────────────────────────

  /// Primary event tag (first in [eventTags]), null if none.
  String? get eventTag => eventTags.isEmpty ? null : eventTags.first;

  /// Primary content hash (first in [contentHashes]).
  String get contentHash => contentHashes.first;

  /// Primary local file path (first in [mediaPaths]), null if not cached.
  String? get mediaPath => mediaPaths.isEmpty ? null : mediaPaths.first;

  bool get hasGps => latitude != null && longitude != null;

  int get displayLikeCount => likeCount + (isLikedByMe ? 1 : 0);

  bool get isPendingRetry => deliveryState == PostDeliveryState.failedToSend;

  /// Whether this post is a Spot check-in with a named place.
  bool get isSpotCheckIn => spotName != null && spotName!.isNotEmpty;

  // ── Serialisation ──────────────────────────────────────────────────────────

  Map<String, dynamic> toJson() => {
    'id': id,
    'pubkey': pubkey,
    'authorDisplayName': authorDisplayName,
    'authorAvatarContentHash': authorAvatarContentHash,
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
    'isTextOnly': isTextOnly,
    'previewBase64': previewBase64,
    'previewMimeType': previewMimeType,
    'sourceType': sourceType.name,
    'caption': caption,
    'replyToId': replyToId,
    'tags': tags,
    'nostrEventId': nostrEventId,
    'spotName': spotName,
    'visibleLocationLabel': visibleLocationLabel,
    'replyCount': replyCount,
    'likeCount': likeCount,
    'isLikedByMe': isLikedByMe,
    'deliveryState': deliveryState.name,
    'lastPublishError': lastPublishError,
  };

  factory MediaPost.fromJson(Map<String, dynamic> json) => MediaPost(
    id: json['id'] as String,
    pubkey: json['pubkey'] as String,
    authorDisplayName: json['authorDisplayName'] as String?,
    authorAvatarContentHash: json['authorAvatarContentHash'] as String?,
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
    isTextOnly: json['isTextOnly'] as bool? ?? false,
    previewBase64: json['previewBase64'] as String?,
    previewMimeType: json['previewMimeType'] as String?,
    sourceType: _parseSourceType(json['sourceType'] as String?),
    caption: json['caption'] as String?,
    replyToId: json['replyToId'] as String?,
    tags: List<String>.from(json['tags'] as List? ?? []),
    nostrEventId: json['nostrEventId'] as String,
    spotName: json['spotName'] as String?,
    visibleLocationLabel: json['visibleLocationLabel'] as String?,
    replyCount: json['replyCount'] as int? ?? 0,
    likeCount: json['likeCount'] as int? ?? 0,
    isLikedByMe: json['isLikedByMe'] as bool? ?? false,
    deliveryState: _parseDeliveryState(json['deliveryState'] as String?),
    lastPublishError: json['lastPublishError'] as String?,
  );

  MediaPost copyWith({
    String? id,
    String? pubkey,
    Object? authorDisplayName = _copyWithUnset,
    Object? authorAvatarContentHash = _copyWithUnset,
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
    bool? isTextOnly,
    String? previewBase64,
    String? previewMimeType,
    PostSourceType? sourceType,
    String? spotName,
    Object? visibleLocationLabel = _copyWithUnset,
    int? replyCount,
    int? likeCount,
    bool? isLikedByMe,
    PostDeliveryState? deliveryState,
    Object? lastPublishError = _copyWithUnset,
  }) => MediaPost(
    id: id ?? this.id,
    pubkey: pubkey ?? this.pubkey,
    authorDisplayName: identical(authorDisplayName, _copyWithUnset)
        ? this.authorDisplayName
        : authorDisplayName as String?,
    authorAvatarContentHash: identical(authorAvatarContentHash, _copyWithUnset)
        ? this.authorAvatarContentHash
        : authorAvatarContentHash as String?,
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
    isTextOnly: isTextOnly ?? this.isTextOnly,
    previewBase64: previewBase64 ?? this.previewBase64,
    previewMimeType: previewMimeType ?? this.previewMimeType,
    sourceType: sourceType ?? this.sourceType,
    caption: caption ?? this.caption,
    replyToId: replyToId ?? this.replyToId,
    tags: tags ?? this.tags,
    nostrEventId: nostrEventId ?? this.nostrEventId,
    spotName: spotName ?? this.spotName,
    visibleLocationLabel: identical(visibleLocationLabel, _copyWithUnset)
        ? this.visibleLocationLabel
        : visibleLocationLabel as String?,
    replyCount: replyCount ?? this.replyCount,
    likeCount: likeCount ?? this.likeCount,
    isLikedByMe: isLikedByMe ?? this.isLikedByMe,
    deliveryState: deliveryState ?? this.deliveryState,
    lastPublishError: identical(lastPublishError, _copyWithUnset)
        ? this.lastPublishError
        : lastPublishError as String?,
  );

  MediaPost mergeLocalStateFrom(MediaPost existing) => copyWith(
    isLikedByMe: existing.isLikedByMe,
    mediaPaths: _mergeMediaPaths(existing.mediaPaths),
    previewBase64: previewBase64 ?? existing.previewBase64,
    previewMimeType: previewMimeType ?? existing.previewMimeType,
    visibleLocationLabel: visibleLocationLabel ?? existing.visibleLocationLabel,
  );

  bool isEquivalentTo(MediaPost other) {
    return id == other.id &&
        pubkey == other.pubkey &&
        authorDisplayName == other.authorDisplayName &&
        authorAvatarContentHash == other.authorAvatarContentHash &&
        _stringListEquals(contentHashes, other.contentHashes) &&
        _stringListEquals(mediaPaths, other.mediaPaths) &&
        ipfsCid == other.ipfsCid &&
        latitude == other.latitude &&
        longitude == other.longitude &&
        capturedAt.isAtSameMomentAs(other.capturedAt) &&
        _stringListEquals(eventTags, other.eventTags) &&
        isDangerMode == other.isDangerMode &&
        isAiGenerated == other.isAiGenerated &&
        isTextOnly == other.isTextOnly &&
        previewBase64 == other.previewBase64 &&
        previewMimeType == other.previewMimeType &&
        sourceType == other.sourceType &&
        isVirtual == other.isVirtual &&
        spotName == other.spotName &&
        visibleLocationLabel == other.visibleLocationLabel &&
        replyCount == other.replyCount &&
        likeCount == other.likeCount &&
        isLikedByMe == other.isLikedByMe &&
        deliveryState == other.deliveryState &&
        lastPublishError == other.lastPublishError &&
        caption == other.caption &&
        replyToId == other.replyToId &&
        _stringListEquals(tags, other.tags) &&
        nostrEventId == other.nostrEventId;
  }

  List<String> _mergeMediaPaths(List<String> existingMediaPaths) {
    if (mediaPaths.isEmpty) return existingMediaPaths;
    if (existingMediaPaths.isEmpty) return mediaPaths;

    final merged = <String>[];
    final maxLength = mediaPaths.length > existingMediaPaths.length
        ? mediaPaths.length
        : existingMediaPaths.length;

    for (var i = 0; i < maxLength; i++) {
      if (i < mediaPaths.length && mediaPaths[i].isNotEmpty) {
        merged.add(mediaPaths[i]);
        continue;
      }
      if (i < existingMediaPaths.length && existingMediaPaths[i].isNotEmpty) {
        merged.add(existingMediaPaths[i]);
      }
    }

    return merged;
  }

  static PostSourceType _parseSourceType(String? value) => switch (value) {
    'secondhand' => PostSourceType.secondhand,
    _ => PostSourceType.firsthand,
  };

  static PostDeliveryState _parseDeliveryState(String? value) =>
      switch (value) {
        'failedToSend' => PostDeliveryState.failedToSend,
        _ => PostDeliveryState.sent,
      };

  static bool _stringListEquals(List<String> left, List<String> right) {
    if (left.length != right.length) return false;
    for (var i = 0; i < left.length; i++) {
      if (left[i] != right[i]) return false;
    }
    return true;
  }

  @override
  String toString() =>
      'MediaPost(id: ${id.substring(0, 8)}..., eventTags: $eventTags, '
      'files: ${contentHashes.length}, isDangerMode: $isDangerMode)';
}
