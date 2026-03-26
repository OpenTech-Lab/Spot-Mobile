import 'package:flutter_test/flutter_test.dart';

import 'package:mobile/models/event_model.dart';
import 'package:mobile/models/media_post.dart';
import 'package:mobile/services/discover_feed_service.dart';
import 'package:mobile/services/feed_scoring_service.dart';

void main() {
  test(
    'visibleTrendingPosts prefers hydrated local posts over stale event rows',
    () {
      final now = DateTime.utc(2026, 3, 26, 12);
      final hydratedLocalPost = _post(
        id: 'post-1',
        capturedAt: now.subtract(const Duration(hours: 1)),
        eventTags: const ['tokyo'],
        mediaPaths: const ['/tmp/post-1.jpg'],
      );
      final staleEventPost = _post(
        id: 'post-1',
        capturedAt: now.subtract(const Duration(hours: 1)),
        eventTags: const ['tokyo'],
      );

      final event = CivicEvent(
        hashtag: 'tokyo',
        title: '#tokyo',
        posts: [staleEventPost],
        firstSeen: now.subtract(const Duration(hours: 1)),
        participantCount: 1,
      );

      final result = visibleTrendingPosts(
        localPosts: [hydratedLocalPost],
        events: [event],
        scoring: const FeedScoringService(),
        now: now,
      );

      expect(result, hasLength(1));
      expect(result.single.id, 'post-1');
      expect(result.single.mediaPaths, ['/tmp/post-1.jpg']);
    },
  );
}

MediaPost _post({
  required String id,
  required DateTime capturedAt,
  List<String> eventTags = const [],
  List<String> mediaPaths = const [],
}) => MediaPost(
  id: id,
  pubkey: 'pubkey-1',
  contentHashes: [id],
  mediaPaths: mediaPaths,
  capturedAt: capturedAt,
  eventTags: eventTags,
  nostrEventId: id,
);
