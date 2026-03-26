import 'package:flutter_test/flutter_test.dart';

import 'package:mobile/models/media_post.dart';
import 'package:mobile/services/post_thread_ordering.dart';

void main() {
  test('thread ordering keeps replies under the visible parent', () {
    final root = _post(id: 'root', capturedAt: DateTime.utc(2026, 3, 23, 10));
    final reply = _post(
      id: 'reply',
      capturedAt: DateTime.utc(2026, 3, 23, 12),
      replyToId: root.nostrEventId,
    );
    final unrelated = _post(
      id: 'other',
      capturedAt: DateTime.utc(2026, 3, 23, 11),
    );

    final entries = buildThreadedPostEntries([root, reply, unrelated]);

    expect(entries.map((entry) => entry.post.nostrEventId).toList(), [
      'root',
      'reply',
      'other',
    ]);
    expect(entries[0].depth, 0);
    expect(entries[1].depth, 1);
    expect(isLastInThread(entries, 0), isFalse);
    expect(isLastInThread(entries, 1), isTrue);
    expect(isLastInThread(entries, 2), isTrue);
  });

  test('thread ordering computes reply counts from visible descendants', () {
    final root = _post(id: 'root', capturedAt: DateTime.utc(2026, 3, 23, 10));
    final child = _post(
      id: 'child',
      capturedAt: DateTime.utc(2026, 3, 23, 11),
      replyToId: root.nostrEventId,
    );
    final grandchild = _post(
      id: 'grandchild',
      capturedAt: DateTime.utc(2026, 3, 23, 12),
      replyToId: child.nostrEventId,
    );

    final entries = buildThreadedPostEntries([root, child, grandchild]);

    expect(entries[0].post.replyCount, 2);
    expect(entries[1].post.replyCount, 1);
    expect(entries[2].post.replyCount, 0);
  });

  test(
    'topLevelThreadPosts returns only root rows ordered by thread activity',
    () {
      final olderRoot = _post(
        id: 'older-root',
        capturedAt: DateTime.utc(2026, 3, 23, 10),
      );
      final olderReply = _post(
        id: 'older-reply',
        capturedAt: DateTime.utc(2026, 3, 23, 11),
        replyToId: olderRoot.nostrEventId,
      );
      final newerRoot = _post(
        id: 'newer-root',
        capturedAt: DateTime.utc(2026, 3, 23, 9),
      );
      final newerReply = _post(
        id: 'newer-reply',
        capturedAt: DateTime.utc(2026, 3, 23, 12),
        replyToId: newerRoot.nostrEventId,
      );

      final roots = topLevelThreadPosts([
        olderRoot,
        olderReply,
        newerRoot,
        newerReply,
      ]);

      expect(roots.map((post) => post.nostrEventId).toList(), [
        'newer-root',
        'older-root',
      ]);
    },
  );

  test('replyPosts returns only replies ordered newest first', () {
    final root = _post(id: 'root', capturedAt: DateTime.utc(2026, 3, 23, 10));
    final olderReply = _post(
      id: 'older-reply',
      capturedAt: DateTime.utc(2026, 3, 23, 11),
      replyToId: root.nostrEventId,
    );
    final newerReply = _post(
      id: 'newer-reply',
      capturedAt: DateTime.utc(2026, 3, 23, 12),
      replyToId: root.nostrEventId,
    );

    final replies = replyPosts([root, olderReply, newerReply]);

    expect(replies.map((post) => post.nostrEventId).toList(), [
      'newer-reply',
      'older-reply',
    ]);
  });

  test('visibleThreadRootIdForPost returns the thread root when visible', () {
    final root = _post(id: 'root', capturedAt: DateTime.utc(2026, 3, 23, 10));
    final reply = _post(
      id: 'reply',
      capturedAt: DateTime.utc(2026, 3, 23, 11),
      replyToId: root.nostrEventId,
    );

    expect(
      visibleThreadRootIdForPost([root, reply], reply.nostrEventId),
      root.nostrEventId,
    );
  });

  test('visibleThreadRootIdForPost falls back to the post id when missing', () {
    final reply = _post(
      id: 'reply',
      capturedAt: DateTime.utc(2026, 3, 23, 11),
      replyToId: 'missing-root',
    );

    expect(
      visibleThreadRootIdForPost([reply], reply.nostrEventId),
      reply.nostrEventId,
    );
  });

  test('threadEntriesForRoot returns only the selected thread subtree', () {
    final root = _post(id: 'root', capturedAt: DateTime.utc(2026, 3, 23, 10));
    final child = _post(
      id: 'child',
      capturedAt: DateTime.utc(2026, 3, 23, 11),
      replyToId: root.nostrEventId,
    );
    final otherRoot = _post(
      id: 'other-root',
      capturedAt: DateTime.utc(2026, 3, 23, 12),
    );

    final entries = threadEntriesForRoot([
      root,
      child,
      otherRoot,
    ], root.nostrEventId);

    expect(entries.map((entry) => entry.post.nostrEventId).toList(), [
      'root',
      'child',
    ]);
    expect(entries.map((entry) => entry.depth).toList(), [0, 1]);
  });
}

MediaPost _post({
  required String id,
  required DateTime capturedAt,
  String? replyToId,
}) => MediaPost(
  id: id,
  pubkey: 'pubkey-$id',
  contentHashes: [id],
  capturedAt: capturedAt,
  eventTags: const ['tokyo'],
  replyToId: replyToId,
  nostrEventId: id,
);
