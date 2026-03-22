import 'dart:math';

import 'package:mobile/models/event_model.dart';
import 'package:mobile/models/media_post.dart';

/// On-device feed scoring for Feed Discovery (v1.5).
///
/// ### Scheme A – Trending
/// ```
/// score = (zaps × 5) + (replies × 3) + (reposts × 2) + (participants × 10)
/// ```
/// Since zaps / reposts are not yet tracked in the local model, they default
/// to 0; replies and participants come from [CivicEvent] data.
///
/// ### Scheme B – Client-side Recommendation (For You + Nearby)
/// ```
/// score =
///   (hashtag_match_count × 10) +
///   (gps_distance_score × 8) +
///   (user_view_time_bonus × 3) +
///   (time_freshness × 2)        // 1 / hours_since_post
/// ```
class FeedScoringService {
  const FeedScoringService();

  // ── Scheme A ──────────────────────────────────────────────────────────────

  /// Computes a trending score for a [CivicEvent].
  ///
  /// Only events from the last 48 h are considered (returns 0.0 otherwise).
  double trendingScore(CivicEvent event) {
    final hoursAgo =
        DateTime.now().difference(event.firstSeen).inHours;
    if (hoursAgo > 48) return 0.0;

    // Count reply posts (posts that are replies = zap/repost proxies)
    final replyCount =
        event.posts.where((p) => p.replyToId != null).length;

    return (replyCount * 3.0) + (event.participantCount * 10.0);
  }

  // ── Scheme B ──────────────────────────────────────────────────────────────

  /// Recommendation score for a single [MediaPost].
  ///
  /// Returns a higher value for posts that match user interests, are nearby,
  /// belong to frequently-viewed hashtags, and were posted recently.
  double recommendationScore({
    required MediaPost post,
    required List<String> userInterests,
    required Map<String, int> viewedHashtags,
    double? userLat,
    double? userLon,
  }) {
    double score = 0.0;

    // Hashtag match
    if (post.eventTag != null) {
      final isMatch = userInterests.contains(post.eventTag);
      if (isMatch) score += 10.0;
    }

    // GPS proximity (Haversine)
    if (post.hasGps && userLat != null && userLon != null) {
      final distKm = haversineKm(
          post.latitude!, post.longitude!, userLat, userLon);
      score += _gpsDistanceScore(distKm) * 8.0;
    }

    // View-time bonus
    if (post.eventTag != null) {
      final views = viewedHashtags[post.eventTag!] ?? 0;
      score += views * 3.0;
    }

    // Freshness: 1 / hours_since_post  (recent → higher)
    final hoursAgo =
        DateTime.now().difference(post.capturedAt).inHours;
    final freshness = hoursAgo > 0 ? 1.0 / hoursAgo : 1.0;
    score += freshness * 2.0;

    return score;
  }

  /// Score based purely on GPS proximity (for Nearby tab).
  ///
  /// Returns a negative distance so sorting descending brings closest first.
  /// Returns `double.negativeInfinity` if the post has no GPS.
  double nearbyScore(MediaPost post, double userLat, double userLon) {
    if (!post.hasGps) return double.negativeInfinity;
    return -haversineKm(
        post.latitude!, post.longitude!, userLat, userLon);
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  double _gpsDistanceScore(double km) {
    if (km < 1.0) return 1.0;
    if (km < 5.0) return 0.8;
    if (km < 20.0) return 0.5;
    if (km < 50.0) return 0.3;
    return 0.0;
  }

  // ── Haversine ─────────────────────────────────────────────────────────────

  /// Returns the great-circle distance in kilometres between two coordinates.
  static double haversineKm(
      double lat1, double lon1, double lat2, double lon2) {
    const r = 6371.0;
    final dlat = _rad(lat2 - lat1);
    final dlon = _rad(lon2 - lon1);
    final a = sin(dlat / 2) * sin(dlat / 2) +
        cos(_rad(lat1)) * cos(_rad(lat2)) * sin(dlon / 2) * sin(dlon / 2);
    return r * 2 * atan2(sqrt(a), sqrt(1 - a));
  }

  static double _rad(double deg) => deg * pi / 180;
}
