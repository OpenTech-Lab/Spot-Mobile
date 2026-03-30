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

  test(
    'removeMatchingPost removes duplicate local variants for the same post',
    () async {
      final legacyLocal = _post(
        id: 'legacy-local-id',
        nostrEventId: 'legacy-local-id',
      );
      final remoteVariant = _post(
        id: 'remote-uuid',
        nostrEventId: 'remote-uuid',
      ).copyWith(contentHashes: legacyLocal.contentHashes);
      final unrelated = _post(id: 'other-post');

      await LocalPostStore.instance.savePosts([
        legacyLocal,
        remoteVariant,
        unrelated,
      ]);

      await LocalPostStore.instance.removeMatchingPost(remoteVariant);

      final posts = await LocalPostStore.instance.loadPosts(
        authorPubkey: 'author-a',
        includeFailedToSend: true,
      );

      expect(posts.map((post) => post.id), ['other-post']);
    },
  );

  test(
    'updateAuthorProfile rewrites saved posts for the matching pubkey',
    () async {
      final original = _post(id: 'author-post');
      final otherAuthor = _post(id: 'other-post', pubkey: 'author-b');

      await LocalPostStore.instance.savePosts([original, otherAuthor]);
      await LocalPostStore.instance.updateAuthorProfile(
        authorPubkey: 'author-a',
        displayName: 'Citizen Tokyo',
        avatarContentHash: 'avatar-hash-1',
      );

      final posts = await LocalPostStore.instance.loadPosts(
        includeFailedToSend: true,
      );
      final updated = posts.firstWhere((post) => post.id == 'author-post');
      final untouched = posts.firstWhere((post) => post.id == 'other-post');

      expect(updated.authorDisplayName, 'Citizen Tokyo');
      expect(updated.authorAvatarContentHash, 'avatar-hash-1');
      expect(untouched.authorDisplayName, isNull);
      expect(untouched.authorAvatarContentHash, isNull);
    },
  );

  test('runWithWritesPaused prevents background saves from repopulating data', () async {
    await LocalPostStore.instance.savePost(_post(id: 'original-post'));

    await LocalPostStore.instance.runWithWritesPaused(() async {
      await LocalPostStore.instance.clearAll(force: true);
      await LocalPostStore.instance.savePost(_post(id: 'repopulated-post'));
    });

    final posts = await LocalPostStore.instance.loadPosts(
      includeFailedToSend: true,
    );

    expect(posts, isEmpty);
  });
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
