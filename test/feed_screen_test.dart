import 'package:flutter_test/flutter_test.dart';

import 'package:mobile/models/media_post.dart';
import 'package:mobile/screens/feed_screen.dart';

void main() {
  test('visibleFollowingPosts excludes the local user posts', () {
    final ownPost = _post(id: 'own-post', pubkey: 'self-pubkey');
    final otherPost = _post(id: 'other-post', pubkey: 'other-pubkey');

    final visible = visibleFollowingPosts(
      [ownPost, otherPost],
      selfPubkey: 'self-pubkey',
      followedPubkeys: const {},
      followedTags: const {},
    );

    expect(visible, isEmpty);
  });

  test('visibleFollowingPosts still includes followed authors and tags', () {
    final ownFollowedTagPost = _post(
      id: 'self-followed-tag',
      pubkey: 'self-pubkey',
      eventTags: const ['tokyo'],
    );
    final followedAuthorPost = _post(id: 'followed-author', pubkey: 'author-a');
    final followedTagPost = _post(
      id: 'followed-tag',
      pubkey: 'author-b',
      eventTags: const ['tokyo'],
    );

    final visible = visibleFollowingPosts(
      [ownFollowedTagPost, followedAuthorPost, followedTagPost],
      selfPubkey: 'self-pubkey',
      followedPubkeys: const {'author-a'},
      followedTags: const {'tokyo'},
    );

    expect(visible, [followedAuthorPost, followedTagPost]);
  });

  test('visibleFollowingPosts hides blocked authors', () {
    final blockedFollowedAuthorPost = _post(
      id: 'blocked-author',
      pubkey: 'author-a',
    );
    final blockedFollowedTagPost = _post(
      id: 'blocked-tag',
      pubkey: 'author-b',
      eventTags: const ['tokyo'],
    );
    final visibleAuthorPost = _post(id: 'visible-author', pubkey: 'author-c');

    final visible = visibleFollowingPosts(
      [blockedFollowedAuthorPost, blockedFollowedTagPost, visibleAuthorPost],
      selfPubkey: 'self-pubkey',
      followedPubkeys: const {'author-a', 'author-c'},
      followedTags: const {'tokyo'},
      blockedPubkeys: const {'author-a', 'author-b'},
    );

    expect(visible, [visibleAuthorPost]);
  });
}

MediaPost _post({
  required String id,
  required String pubkey,
  List<String> eventTags = const ['osaka'],
}) => MediaPost(
  id: id,
  pubkey: pubkey,
  contentHashes: [id],
  capturedAt: DateTime.utc(2026, 3, 24),
  eventTags: eventTags,
  nostrEventId: id,
);
