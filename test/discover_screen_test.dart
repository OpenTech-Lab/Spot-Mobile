import 'package:flutter_test/flutter_test.dart';

import 'package:mobile/models/media_post.dart';
import 'package:mobile/screens/discover_screen.dart';

void main() {
  test('discoverFollowableTagForQuery normalizes hash-prefixed tags', () {
    expect(discoverFollowableTagForQuery('  #Test, '), 'test');
    expect(discoverFollowableTagForQuery('test'), isNull);
  });

  test('discover search matches keyword in caption', () {
    final posts = [
      _post(id: '1', caption: 'Fire near station'),
      _post(id: '2', caption: 'Calm morning'),
    ];

    final visible = visibleDiscoverThreads(posts, query: 'fire');

    expect(visible.map((post) => post.id), ['1']);
  });

  test('discover search matches tags with leading hash syntax', () {
    final posts = [
      _post(id: '1', eventTags: const ['test']),
      _post(id: '2', eventTags: const ['weather']),
    ];

    final visible = visibleDiscoverThreads(posts, query: '#test');

    expect(visible.map((post) => post.id), ['1']);
  });

  test('discover search returns the root thread when a reply matches', () {
    final root = _post(
      id: 'root',
      nostrEventId: 'root-event',
      caption: 'Parent thread',
    );
    final reply = _post(
      id: 'reply',
      nostrEventId: 'reply-event',
      replyToId: 'root-event',
      caption: 'Witness saw smoke nearby',
    );
    final unrelated = _post(id: 'other', caption: 'Nothing relevant');

    final visible = visibleDiscoverThreads([
      root,
      reply,
      unrelated,
    ], query: 'smoke');

    expect(visible.map((post) => post.id), ['root']);
  });
}

MediaPost _post({
  required String id,
  String? nostrEventId,
  String? replyToId,
  String? caption,
  List<String> eventTags = const ['general'],
  List<String> tags = const [],
}) => MediaPost(
  id: id,
  pubkey: 'pubkey-$id',
  contentHashes: [id],
  capturedAt: DateTime.utc(2026, 3, 26),
  eventTags: eventTags,
  tags: tags,
  caption: caption,
  replyToId: replyToId,
  nostrEventId: nostrEventId ?? id,
);
