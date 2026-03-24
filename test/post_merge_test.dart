import 'package:flutter_test/flutter_test.dart';

import 'package:mobile/models/media_post.dart';
import 'package:mobile/services/post_merge.dart';

void main() {
  test('MediaPost json roundtrip preserves local liked state', () {
    final post = _post(likeCount: 2, isLikedByMe: true);

    final decoded = MediaPost.fromJson(post.toJson());

    expect(decoded.isLikedByMe, isTrue);
    expect(decoded.displayLikeCount, 3);
  });

  test('mergePostsPreservingLocalState keeps local liked state on refresh', () {
    final current = [
      _post(
        likeCount: 2,
        isLikedByMe: true,
        caption: 'old caption',
        capturedAt: DateTime.utc(2026, 3, 22),
      ),
    ];
    final incoming = [
      _post(
        likeCount: 2,
        caption: 'new caption',
        capturedAt: DateTime.utc(2026, 3, 23),
      ),
    ];

    final merged = mergePostsPreservingLocalState(current, incoming);

    expect(merged, hasLength(1));
    expect(merged.single.caption, 'new caption');
    expect(merged.single.isLikedByMe, isTrue);
    expect(merged.single.displayLikeCount, 3);
  });

  test('mergePostsPreservingLocalState keeps local media paths on refresh', () {
    final current = [
      _post(
        mediaPaths: const ['/tmp/cached-image.jpg'],
        capturedAt: DateTime.utc(2026, 3, 22),
      ),
    ];
    final incoming = [
      _post(caption: 'fresh metadata', capturedAt: DateTime.utc(2026, 3, 23)),
    ];

    final merged = mergePostsPreservingLocalState(current, incoming);

    expect(merged, hasLength(1));
    expect(merged.single.caption, 'fresh metadata');
    expect(merged.single.mediaPaths, ['/tmp/cached-image.jpg']);
  });

  test('replacePostsById applies a local liked-state update', () {
    final current = [_post(likeCount: 2)];
    final updated = _post(likeCount: 2, isLikedByMe: true);

    final merged = replacePostsById(current, [updated]);

    expect(merged, hasLength(1));
    expect(merged.single.isLikedByMe, isTrue);
    expect(merged.single.displayLikeCount, 3);
  });

  test('orderedPostsEqual catches same-length media upgrades', () {
    final current = [
      _post(previewBase64: 'YWJj', previewMimeType: 'image/jpeg'),
    ];
    final updated = [
      _post(
        mediaPaths: const ['/tmp/local-image.jpg'],
        previewBase64: 'YWJj',
        previewMimeType: 'image/jpeg',
      ),
    ];

    expect(orderedPostsEqual(current, updated), isFalse);
  });
}

MediaPost _post({
  int likeCount = 0,
  bool isLikedByMe = false,
  String? caption,
  DateTime? capturedAt,
  List<String> mediaPaths = const [],
  String? previewBase64,
  String? previewMimeType,
}) => MediaPost(
  id: 'post-id',
  pubkey: 'pubkey',
  contentHashes: const ['post-id'],
  mediaPaths: mediaPaths,
  capturedAt: capturedAt ?? DateTime.utc(2026, 3, 23),
  eventTags: const ['tokyo'],
  caption: caption,
  likeCount: likeCount,
  isLikedByMe: isLikedByMe,
  previewBase64: previewBase64,
  previewMimeType: previewMimeType,
  nostrEventId: 'post-id',
);
