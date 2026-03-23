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
