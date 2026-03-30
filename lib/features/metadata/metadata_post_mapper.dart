import 'package:mobile/models/media_post.dart';

abstract final class MetadataPostMapper {
  MetadataPostMapper._();

  static Map<String, dynamic> toInsertRow(MediaPost post) => {
    'event_hashtag': post.eventTag,
    'event_tags': post.eventTags,
    'content_hashes': post.contentHashes,
    'media_type': _primaryMediaType(post),
    'caption': post.caption,
    'latitude': post.latitude,
    'longitude': post.longitude,
    'preview_base64': post.previewBase64,
    'preview_mime_type': post.previewMimeType,
    'source_type': post.sourceType.name,
    'is_danger_mode': post.isDangerMode,
    'is_virtual': post.isVirtual,
    'is_ai_generated': post.isAiGenerated,
    'is_text_only': post.isTextOnly,
    'reply_to_id': post.replyToId,
    'spot_name': post.spotName,
    'tags': post.tags,
    'created_at': post.capturedAt.toUtc().toIso8601String(),
  };

  static Map<String, dynamic> toPublishRpcParams(MediaPost post) => {
    'p_event_tags': post.eventTags,
    'p_content_hashes': post.contentHashes,
    'p_media_type': _primaryMediaType(post),
    'p_caption': post.caption,
    'p_latitude': post.latitude,
    'p_longitude': post.longitude,
    'p_preview_base64': post.previewBase64,
    'p_preview_mime_type': post.previewMimeType,
    'p_source_type': post.sourceType.name,
    'p_is_danger_mode': post.isDangerMode,
    'p_is_virtual': post.isVirtual,
    'p_is_ai_generated': post.isAiGenerated,
    'p_is_text_only': post.isTextOnly,
    'p_reply_to_id': _normalizedOptionalText(post.replyToId),
    'p_spot_name': _normalizedOptionalText(post.spotName),
    'p_tags': post.tags,
    'p_created_at': post.capturedAt.toUtc().toIso8601String(),
  };

  static MediaPost fromRow(
    Map<String, dynamic> row, {
    required String authorKey,
    String? authorDisplayName,
    String? authorAvatarContentHash,
  }) {
    final id = row['id'].toString();
    final eventTags = row['event_tags'] != null
        ? List<String>.from(row['event_tags'] as List)
        : (row['event_hashtag'] != null
              ? [row['event_hashtag'].toString()]
              : const <String>[]);
    final contentHashes = row['content_hashes'] != null
        ? List<String>.from(row['content_hashes'] as List)
        : <String>[id];

    return MediaPost(
      id: id,
      pubkey: authorKey,
      authorDisplayName: authorDisplayName,
      authorAvatarContentHash: authorAvatarContentHash,
      contentHashes: contentHashes.isEmpty ? <String>[id] : contentHashes,
      latitude: (row['latitude'] as num?)?.toDouble(),
      longitude: (row['longitude'] as num?)?.toDouble(),
      capturedAt: DateTime.parse(row['created_at'].toString()).toUtc(),
      eventTags: eventTags,
      isDangerMode: row['is_danger_mode'] as bool? ?? false,
      isVirtual: row['is_virtual'] as bool? ?? false,
      isAiGenerated: row['is_ai_generated'] as bool? ?? false,
      isTextOnly: row['is_text_only'] as bool? ?? false,
      previewBase64: row['preview_base64'] as String?,
      previewMimeType: row['preview_mime_type'] as String?,
      sourceType: row['source_type'] == 'secondhand'
          ? PostSourceType.secondhand
          : PostSourceType.firsthand,
      caption: row['caption'] as String?,
      replyToId: row['reply_to_id']?.toString(),
      tags: row['tags'] != null
          ? List<String>.from(row['tags'] as List)
          : const <String>[],
      nostrEventId: id,
      spotName: row['spot_name'] as String?,
      replyCount: row['reply_count'] as int? ?? 0,
      likeCount: row['like_count'] as int? ?? 0,
    );
  }

  static String _primaryMediaType(MediaPost post) {
    if (post.isTextOnly) return 'text';
    final path = post.mediaPath?.toLowerCase() ?? '';
    if (path.endsWith('.mp4') ||
        path.endsWith('.mov') ||
        path.endsWith('.avi') ||
        path.endsWith('.mkv') ||
        path.endsWith('.webm')) {
      return 'video';
    }
    return 'image';
  }

  static String? _normalizedOptionalText(String? value) {
    final normalized = value?.trim();
    if (normalized == null || normalized.isEmpty) return null;
    return normalized;
  }
}
