import 'dart:math';

import 'package:mobile/models/event_model.dart';
import 'package:mobile/models/media_post.dart';
import 'package:mobile/models/witness_model.dart';

/// Computes EBES trust scores for evidence items and civic events.
///
/// All computation is local (on-device) with no external calls.
///
/// ### Evidence trust formula
/// ```
/// EvidenceScore =
///   w1 * SourceScore +
///   w2 * MediaIntegrity +
///   w3 * GeoMatch +
///   w4 * TimeMatch +
///   w5 * CrossEvidenceScore
/// ```
///
/// ### Witness weight formula
/// Weight is a function of the poster's history (proxied by post count),
/// geo proximity to the event, and temporal proximity.
class TrustService {
  const TrustService();

  // ── Evidence score weights ─────────────────────────────────────────────────

  static const double _w1 = 0.25; // SourceScore
  static const double _w2 = 0.20; // MediaIntegrity
  static const double _w3 = 0.20; // GeoMatch
  static const double _w4 = 0.15; // TimeMatch
  static const double _w5 = 0.20; // CrossEvidenceScore

  // ── Evidence trust ────────────────────────────────────────────────────────

  /// Returns a 0.0–1.0 trust score for a single piece of evidence.
  ///
  /// [postCountByPubkey] is a map from pubkey → number of posts the author has
  /// made, used as a proxy reputation signal.
  double computeEvidenceTrust(
    MediaPost post,
    CivicEvent event, {
    Map<String, int> postCountByPubkey = const {},
  }) {
    final source = _sourceScore(post.pubkey, postCountByPubkey);
    final integrity = _mediaIntegrityScore(post);
    final geoMatch = _geoMatchScore(post, event);
    final timeMatch = _timeMatchScore(post, event);
    final crossEvidence = _crossEvidenceScore(event);

    return (_w1 * source +
            _w2 * integrity +
            _w3 * geoMatch +
            _w4 * timeMatch +
            _w5 * crossEvidence)
        .clamp(0.0, 1.0);
  }

  // ── Event trust ───────────────────────────────────────────────────────────

  /// Returns a 0.0–1.0 aggregate trust score for an entire [CivicEvent].
  ///
  /// High-quality evidence outweighs quantity; conflicting witnesses
  /// reduce the score; clustered / low-diversity inputs are discounted.
  double computeEventTrust(
    CivicEvent event,
    List<Witness> witnesses, {
    Map<String, int> postCountByPubkey = const {},
  }) {
    if (event.posts.isEmpty) return 0.0;

    // Average evidence trust
    final avgEvidence = event.posts
            .map((p) =>
                computeEvidenceTrust(p, event, postCountByPubkey: postCountByPubkey))
            .fold(0.0, (a, b) => a + b) /
        event.posts.length;

    // Witness contribution
    final confirmedWeight = witnesses
        .where((w) => w.type == WitnessType.confirm || w.type == WitnessType.seen)
        .fold(0.0, (sum, w) => sum + w.weight);
    final denyWeight = witnesses
        .where((w) => w.type == WitnessType.deny)
        .fold(0.0, (sum, w) => sum + w.weight);

    final witnessBonus = (confirmedWeight * 0.1).clamp(0.0, 0.3);
    final conflictPenalty = (denyWeight * 0.2).clamp(0.0, 0.4);

    // Source diversity bonus (more unique authors → higher confidence)
    final diversityBonus = (event.participantCount >= 3 ? 0.1 : 0.0);

    return (avgEvidence + witnessBonus + diversityBonus - conflictPenalty)
        .clamp(0.0, 1.0);
  }

  // ── Event status ──────────────────────────────────────────────────────────

  /// Maps a trust score + witnesses to a [EventStatus] label.
  EventStatus statusFromScore(double score, List<Witness> witnesses) {
    final totalWeight = witnesses.fold(0.0, (sum, w) => sum + w.weight);
    final denyWeight = witnesses
        .where((w) => w.type == WitnessType.deny)
        .fold(0.0, (sum, w) => sum + w.weight);

    final conflictRatio =
        totalWeight > 0 ? denyWeight / totalWeight : 0.0;

    if (conflictRatio > 0.3) return EventStatus.conflicted;
    if (score >= 0.65) return EventStatus.highConfidence;
    return EventStatus.unverified;
  }

  // ── Witness weight ────────────────────────────────────────────────────────

  /// Computes a weight 0.0–1.0 for a [Witness] signal.
  ///
  /// Factors: geo proximity to event, time proximity, post count (reputation proxy).
  double witnessWeight(
    Witness witness,
    CivicEvent event, {
    Map<String, int> postCountByPubkey = const {},
  }) {
    final repScore = _sourceScore(witness.userId, postCountByPubkey);

    final geoScore = (witness.lat != null &&
            witness.lon != null &&
            event.centerLat != null)
        ? _geoScoreFromDistance(
            _haversineKm(witness.lat!, witness.lon!,
                event.centerLat!, event.centerLon!))
        : 0.5;

    final hoursDiff =
        DateTime.now().difference(witness.timestamp).inHours.abs();
    final timeScore = hoursDiff <= 1
        ? 1.0
        : hoursDiff <= 6
            ? 0.7
            : hoursDiff <= 24
                ? 0.4
                : 0.2;

    return ((repScore * 0.4) + (geoScore * 0.4) + (timeScore * 0.2))
        .clamp(0.0, 1.0);
  }

  // ── Private helpers ───────────────────────────────────────────────────────

  /// Reputation proxy: more posts → higher trust (capped at 1.0 at 10 posts).
  double _sourceScore(String pubkey, Map<String, int> postCounts) {
    final count = postCounts[pubkey] ?? 0;
    return (count / 10.0).clamp(0.1, 1.0);
  }

  /// Media integrity: GPS presence and danger mode absence raise the score.
  /// A real implementation would also check perceptual hash uniqueness.
  double _mediaIntegrityScore(MediaPost post) {
    if (post.isDangerMode) return 0.5; // metadata stripped
    if (post.hasGps) return 0.85;
    return 0.6;
  }

  /// How well the post's GPS location matches the event's known centre.
  double _geoMatchScore(MediaPost post, CivicEvent event) {
    if (!post.hasGps || event.centerLat == null) return 0.5;
    final dist = _haversineKm(
        post.latitude!, post.longitude!, event.centerLat!, event.centerLon!);
    return _geoScoreFromDistance(dist);
  }

  double _geoScoreFromDistance(double km) {
    if (km < 0.5) return 1.0;
    if (km < 2.0) return 0.7;
    if (km < 10.0) return 0.4;
    return 0.1;
  }

  /// How well the post's timestamp aligns with the event's start time.
  double _timeMatchScore(MediaPost post, CivicEvent event) {
    final diffHours =
        post.capturedAt.difference(event.firstSeen).abs().inHours;
    if (diffHours < 1) return 1.0;
    if (diffHours < 6) return 0.8;
    if (diffHours < 24) return 0.5;
    return 0.2;
  }

  /// Source diversity: more unique contributors → higher cross-evidence score.
  double _crossEvidenceScore(CivicEvent event) {
    final unique = event.participantCount;
    if (unique >= 5) return 1.0;
    if (unique >= 3) return 0.7;
    if (unique >= 2) return 0.5;
    return 0.2;
  }

  // ── Geo math ──────────────────────────────────────────────────────────────

  static double _haversineKm(
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
