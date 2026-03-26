import 'package:mobile/models/event_model.dart';
import 'package:mobile/models/media_post.dart';
import 'package:mobile/services/feed_scoring_service.dart';

List<MediaPost> visibleTrendingPosts({
  required List<MediaPost> localPosts,
  required List<CivicEvent> events,
  required FeedScoringService scoring,
  DateTime? now,
}) {
  final currentTime = now ?? DateTime.now();
  final postsByHashtag = <String, List<MediaPost>>{};
  final untaggedPosts = <MediaPost>[];

  for (final post in localPosts) {
    final hashtag = post.eventTag;
    if (hashtag == null || hashtag == '_unsorted') {
      untaggedPosts.add(post);
      continue;
    }
    postsByHashtag.putIfAbsent(hashtag, () => <MediaPost>[]).add(post);
  }

  for (final posts in postsByHashtag.values) {
    posts.sort((a, b) => b.capturedAt.compareTo(a.capturedAt));
  }
  untaggedPosts.sort((a, b) => b.capturedAt.compareTo(a.capturedAt));

  final scoredEvents =
      events
          .where(
            (event) => currentTime.difference(event.firstSeen).inHours <= 48,
          )
          .toList()
        ..sort(
          (a, b) =>
              scoring.trendingScore(b).compareTo(scoring.trendingScore(a)),
        );

  final result = <MediaPost>[];
  final seen = <String>{};

  for (final event in scoredEvents) {
    final preferredPosts = postsByHashtag[event.hashtag];
    final candidates = preferredPosts != null && preferredPosts.isNotEmpty
        ? preferredPosts
        : event.postsByNewest;
    for (final post in candidates) {
      if (seen.add(post.id)) {
        result.add(post);
      }
    }
  }

  for (final post in untaggedPosts) {
    if (seen.add(post.id)) {
      result.add(post);
    }
  }

  return result;
}
