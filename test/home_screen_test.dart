import 'package:flutter_test/flutter_test.dart';

import 'package:mobile/models/event_model.dart';
import 'package:mobile/models/media_post.dart';
import 'package:mobile/screens/home_screen.dart';

void main() {
  test('orderedFavoriteEventTags prioritizes tags with live events', () {
    final tags = orderedFavoriteEventTags(
      followedTags: const ['Kyoto', 'TOKYO', 'osaka'],
      events: [
        _event(
          hashtag: 'tokyo',
          firstSeen: DateTime.utc(2026, 3, 20),
          latestPostAt: DateTime.utc(2026, 3, 25),
        ),
        _event(
          hashtag: 'osaka',
          firstSeen: DateTime.utc(2026, 3, 18),
          latestPostAt: DateTime.utc(2026, 3, 26),
        ),
      ],
    );

    expect(tags, ['osaka', 'tokyo', 'kyoto']);
  });

  test('eventForFavoriteTag matches events case-insensitively', () {
    final event = _event(hashtag: 'Tokyo');

    final matched = eventForFavoriteTag([event], 'tokyo');

    expect(matched, same(event));
  });
}

CivicEvent _event({
  required String hashtag,
  DateTime? firstSeen,
  DateTime? latestPostAt,
}) {
  final createdAt = firstSeen ?? DateTime.utc(2026, 3, 20);
  return CivicEvent(
    hashtag: hashtag,
    title: '#$hashtag',
    posts: [
      MediaPost(
        id: 'post-$hashtag',
        pubkey: 'pubkey-$hashtag',
        contentHashes: const ['hash'],
        capturedAt: latestPostAt ?? createdAt,
        eventTags: [hashtag],
        nostrEventId: 'event-$hashtag',
      ),
    ],
    firstSeen: createdAt,
    participantCount: 1,
  );
}
