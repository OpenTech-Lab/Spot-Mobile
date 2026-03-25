import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/models/media_post.dart';
import 'package:mobile/models/asset_transport_policy.dart';
import 'package:mobile/services/post_thread_ordering.dart';
import 'package:mobile/services/post_merge.dart';

void main() {
  test('Newest posts correctly identified and sorted', () {
    final oldPost = MediaPost(
      id: 'old',
      pubkey: 'A',
      contentHashes: ['old_hash'],
      capturedAt: DateTime.now().subtract(Duration(days: 1)),
      eventTags: ['test'],
      nostrEventId: 'old',
      mediaPaths: [],
      isTextOnly: false,
    );

    final newPost = MediaPost(
      id: 'new',
      pubkey: 'B',
      contentHashes: ['new_hash'],
      capturedAt: DateTime.now().toUtc(),
      eventTags: ['test'],
      nostrEventId: 'new',
      mediaPaths: ['/tmp/test.jpg'],
      isTextOnly: false,
    );

    final merged = mergePostsPreservingLocalState([oldPost], [newPost]);
    expect(merged.first.id, 'new');

    final roots = topLevelThreadPosts(merged);
    expect(roots.length, 2);
    expect(roots.first.id, 'new'); // Should be top
    print("Test passed. Merged length: ${merged.length}. First ID: ${roots.first.id}");
  });
}
