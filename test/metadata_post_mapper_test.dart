import 'package:flutter_test/flutter_test.dart';

import 'package:mobile/features/metadata/metadata_post_mapper.dart';
import 'package:mobile/models/media_post.dart';

void main() {
  test('toInsertRow preserves Supabase metadata fields', () {
    final post = MediaPost(
      id: 'local-id',
      pubkey: 'pubkey',
      contentHashes: const ['hash-1', 'hash-2'],
      mediaPaths: const ['/tmp/photo.jpg'],
      latitude: 35.68,
      longitude: 139.76,
      capturedAt: DateTime.utc(2026, 3, 26, 10, 30),
      eventTags: const ['tokyo', 'summit'],
      isDangerMode: true,
      isVirtual: false,
      isAiGenerated: true,
      isTextOnly: false,
      sourceType: PostSourceType.secondhand,
      caption: 'hello',
      replyToId: 'parent-id',
      tags: const ['source:secondhand'],
      nostrEventId: 'local-id',
      spotName: 'Tokyo Station',
      previewBase64: 'YWJj',
      previewMimeType: 'image/jpeg',
    );

    final row = MetadataPostMapper.toInsertRow(post);

    expect(row['event_hashtag'], 'tokyo');
    expect(row['event_tags'], ['tokyo', 'summit']);
    expect(row['content_hashes'], ['hash-1', 'hash-2']);
    expect(row['media_type'], 'image');
    expect(row['is_danger_mode'], isTrue);
    expect(row['is_ai_generated'], isTrue);
    expect(row['source_type'], 'secondhand');
    expect(row['reply_to_id'], 'parent-id');
  });

  test('fromRow maps Supabase post rows back to MediaPost', () {
    final mapped = MetadataPostMapper.fromRow({
      'id': 'post-uuid',
      'event_hashtag': 'tokyo',
      'event_tags': ['tokyo', 'summit'],
      'content_hashes': ['hash-1'],
      'caption': 'caption',
      'latitude': 35.68,
      'longitude': 139.76,
      'created_at': '2026-03-26T10:30:00Z',
      'is_danger_mode': false,
      'is_virtual': true,
      'is_ai_generated': false,
      'is_text_only': false,
      'preview_base64': 'YWJj',
      'preview_mime_type': 'image/jpeg',
      'source_type': 'firsthand',
      'reply_to_id': 'parent-id',
      'tags': ['source:firsthand'],
      'spot_name': 'Tokyo Station',
      'reply_count': 4,
      'like_count': 9,
    }, authorKey: 'legacy-pubkey');

    expect(mapped.id, 'post-uuid');
    expect(mapped.pubkey, 'legacy-pubkey');
    expect(mapped.eventTags, ['tokyo', 'summit']);
    expect(mapped.caption, 'caption');
    expect(mapped.latitude, 35.68);
    expect(mapped.longitude, 139.76);
    expect(mapped.isVirtual, isTrue);
    expect(mapped.replyToId, 'parent-id');
    expect(mapped.replyCount, 4);
    expect(mapped.likeCount, 9);
  });
}
