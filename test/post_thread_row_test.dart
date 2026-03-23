import 'package:flutter_test/flutter_test.dart';

import 'package:mobile/models/media_post.dart';
import 'package:mobile/widgets/post_thread_row.dart';

void main() {
  test('visibleThreadTagsForPost shows only category tag on root posts', () {
    final post = _post(eventTags: const ['tokyo', 'news', 'urgent']);

    expect(visibleThreadTagsForPost(post), ['tokyo']);
  });

  test('visibleThreadTagsForPost shows only sub tags on replies', () {
    final post = _post(
      eventTags: const ['tokyo', 'news', 'urgent'],
      replyToId: 'root-id',
    );

    expect(visibleThreadTagsForPost(post), ['news', 'urgent']);
  });

  test('visibleThreadTagsForPost hides category-only tags on replies', () {
    final post = _post(eventTags: const ['tokyo'], replyToId: 'root-id');

    expect(visibleThreadTagsForPost(post), isEmpty);
  });
}

MediaPost _post({required List<String> eventTags, String? replyToId}) =>
    MediaPost(
      id: 'post-id',
      pubkey: 'pubkey',
      contentHashes: const ['post-id'],
      capturedAt: DateTime.utc(2026, 3, 23),
      eventTags: eventTags,
      replyToId: replyToId,
      nostrEventId: 'post-id',
    );
