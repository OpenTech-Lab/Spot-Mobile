import 'package:mobile/features/event/event_ordering.dart';
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

  test(
    'orderedFavoriteEventTags uses newer reply activity when it beats the last post',
    () {
      final tags = orderedFavoriteEventTags(
        followedTags: const ['tokyo', 'osaka'],
        events: [
          _event(
            hashtag: 'tokyo',
            firstSeen: DateTime.utc(2026, 3, 20),
            latestPostAt: DateTime.utc(2026, 3, 25),
          ),
          _event(
            hashtag: 'osaka',
            firstSeen: DateTime.utc(2026, 3, 18),
            latestPostAt: DateTime.utc(2026, 3, 24),
            latestReplyAt: DateTime.utc(2026, 3, 26),
          ),
        ],
      );

      expect(tags, ['osaka', 'tokyo']);
    },
  );

  test('eventForFavoriteTag matches events case-insensitively', () {
    final event = _event(hashtag: 'Tokyo');

    final matched = eventForFavoriteTag([event], 'tokyo');

    expect(matched, same(event));
  });

  test(
    'eventsForFollowedTags keeps only followed-tag events in input order',
    () {
      final followed = eventsForFollowedTags(
        events: [
          _event(hashtag: 'tokyo', firstSeen: DateTime.utc(2026, 3, 26, 10)),
          _event(hashtag: 'osaka', firstSeen: DateTime.utc(2026, 3, 26, 9)),
          _event(hashtag: 'kyoto', firstSeen: DateTime.utc(2026, 3, 26, 8)),
        ],
        followedTags: const ['KYOTO', 'tokyo'],
      );

      expect(followed.map((event) => event.hashtag), ['tokyo', 'kyoto']);
    },
  );

  test(
    'sortEventsByLastActivity defaults to the newest post/reply activity',
    () {
      final ordered = sortEventsByLastActivity([
        _event(
          hashtag: 'tokyo',
          firstSeen: DateTime.utc(2026, 3, 20),
          latestPostAt: DateTime.utc(2026, 3, 25),
        ),
        _event(
          hashtag: 'osaka',
          firstSeen: DateTime.utc(2026, 3, 18),
          latestPostAt: DateTime.utc(2026, 3, 24),
          latestReplyAt: DateTime.utc(2026, 3, 26),
        ),
        _event(
          hashtag: 'kyoto',
          firstSeen: DateTime.utc(2026, 3, 19),
          latestPostAt: DateTime.utc(2026, 3, 27),
        ),
      ]);

      expect(ordered.map((event) => event.hashtag), [
        'kyoto',
        'osaka',
        'tokyo',
      ]);
    },
  );

  test('CivicEvent exposes separate last post and last reply dates', () {
    final event = _event(
      hashtag: 'tokyo',
      firstSeen: DateTime.utc(2026, 3, 20),
      latestPostAt: DateTime.utc(2026, 3, 25, 9),
      latestReplyAt: DateTime.utc(2026, 3, 26, 14),
    );

    expect(event.lastPostAt, DateTime.utc(2026, 3, 25, 9));
    expect(event.lastReplyAt, DateTime.utc(2026, 3, 26, 14));
    expect(event.lastActivityAt, DateTime.utc(2026, 3, 26, 14));
  });

  test('formatEventListDate uses compact local date output', () {
    expect(
      formatEventListDate(DateTime.utc(2026, 3, 29, 13, 45)),
      '2026/03/29',
    );
    expect(formatEventListDate(null), '-');
  });
}

CivicEvent _event({
  required String hashtag,
  DateTime? firstSeen,
  DateTime? latestPostAt,
  DateTime? latestReplyAt,
}) {
  final createdAt = firstSeen ?? DateTime.utc(2026, 3, 20);
  final rootEventId = 'event-$hashtag-root';
  final rootPostAt = latestPostAt ?? createdAt;
  final posts = <MediaPost>[
    MediaPost(
      id: 'post-$hashtag-root',
      pubkey: 'pubkey-$hashtag',
      contentHashes: const ['hash'],
      capturedAt: rootPostAt,
      eventTags: [hashtag],
      nostrEventId: rootEventId,
    ),
  ];

  if (latestReplyAt != null) {
    posts.add(
      MediaPost(
        id: 'post-$hashtag-reply',
        pubkey: 'pubkey-$hashtag-reply',
        contentHashes: const ['hash'],
        capturedAt: latestReplyAt,
        eventTags: [hashtag],
        replyToId: rootEventId,
        nostrEventId: 'event-$hashtag-reply',
      ),
    );
  }

  posts.sort((a, b) => a.capturedAt.compareTo(b.capturedAt));

  return CivicEvent(
    hashtag: hashtag,
    title: '#$hashtag',
    posts: posts,
    firstSeen: createdAt,
    participantCount: 1,
  );
}
