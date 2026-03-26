import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:mobile/models/media_post.dart';
import 'package:mobile/services/local_post_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('spot-local-post-store-');
    LocalPostStore.instance.debugSetStorageDirectory(tempDir);
  });

  tearDown(() async {
    LocalPostStore.instance.debugSetStorageDirectory(null);
    if (tempDir.existsSync()) {
      await tempDir.delete(recursive: true);
    }
  });

  test(
    'loadPosts excludes failed local posts by default but can include them',
    () async {
      final sentPost = _post(id: 'sent-post');
      final failedPost =
          _post(
            id: 'failed-post',
            capturedAt: DateTime.utc(2026, 3, 24, 9, 5),
          ).copyWith(
            deliveryState: PostDeliveryState.failedToSend,
            lastPublishError: 'timeout',
          );

      await LocalPostStore.instance.savePost(sentPost);
      await LocalPostStore.instance.savePost(failedPost);

      final defaultPosts = await LocalPostStore.instance.loadPosts(
        authorPubkey: 'author-a',
      );
      final includingFailed = await LocalPostStore.instance.loadPosts(
        authorPubkey: 'author-a',
        includeFailedToSend: true,
      );

      expect(defaultPosts.map((post) => post.id), ['sent-post']);
      expect(includingFailed.map((post) => post.id), [
        'failed-post',
        'sent-post',
      ]);
      expect(includingFailed.first.lastPublishError, 'timeout');
    },
  );

  test(
    'replacePost swaps a failed local draft with the published event',
    () async {
      final failedPost =
          _post(
            id: 'failed-post',
            capturedAt: DateTime.utc(2026, 3, 24, 9, 0),
          ).copyWith(
            deliveryState: PostDeliveryState.failedToSend,
            lastPublishError: 'publish failed',
          );
      final sentPost = _post(
        id: 'published-event-id',
        nostrEventId: 'published-event-id',
        capturedAt: DateTime.utc(2026, 3, 24, 9, 5),
      );

      await LocalPostStore.instance.savePost(failedPost);
      await LocalPostStore.instance.replacePost(failedPost.id, sentPost);

      final posts = await LocalPostStore.instance.loadPosts(
        authorPubkey: 'author-a',
        includeFailedToSend: true,
      );

      expect(posts, hasLength(1));
      expect(posts.single.id, 'published-event-id');
      expect(posts.single.deliveryState, PostDeliveryState.sent);
      expect(posts.single.lastPublishError, isNull);
    },
  );
}

MediaPost _post({
  required String id,
  String pubkey = 'author-a',
  DateTime? capturedAt,
  String? nostrEventId,
}) => MediaPost(
  id: id,
  pubkey: pubkey,
  contentHashes: [id],
  mediaPaths: const ['/tmp/example.jpg'],
  capturedAt: capturedAt ?? DateTime.utc(2026, 3, 24, 9),
  eventTags: const ['test15'],
  caption: 'hello',
  nostrEventId: nostrEventId ?? id,
);
