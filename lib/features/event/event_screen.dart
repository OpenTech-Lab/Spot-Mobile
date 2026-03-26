import 'dart:math' as math;
import 'dart:ui' as ui show Path;

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:intl/intl.dart';
import 'package:latlong2/latlong.dart';

import 'package:mobile/features/ebes/trust_service.dart';
import 'package:mobile/features/metadata/metadata_service.dart';
import 'package:mobile/models/event_model.dart';
import 'package:mobile/models/media_post.dart';
import 'package:mobile/models/wallet_model.dart';
import 'package:mobile/models/witness_model.dart';
import 'package:mobile/services/follow_service.dart';
import 'package:mobile/theme/spot_theme.dart';

/// Event detail — wiki-like timeline for a [CivicEvent] with EBES trust data.
class EventLocationSpot {
  const EventLocationSpot({
    required this.latitude,
    required this.longitude,
    required this.label,
  });

  final double latitude;
  final double longitude;
  final String label;
}

List<EventLocationSpot> eventLocationSpots(Iterable<MediaPost> posts) {
  return posts
      .where((post) => post.hasGps)
      .map(
        (post) => EventLocationSpot(
          latitude: post.latitude!,
          longitude: post.longitude!,
          label: post.spotName?.trim().isNotEmpty == true
              ? post.spotName!.trim()
              : (post.eventTag?.isNotEmpty == true
                    ? '#${post.eventTag}'
                    : 'Pinned post'),
        ),
      )
      .toList(growable: false);
}

LatLng eventLocationCenter(Iterable<EventLocationSpot> spots) {
  final points = spots.toList(growable: false);
  if (points.isEmpty) return const LatLng(0, 0);
  final latAverage =
      points.map((spot) => spot.latitude).reduce((a, b) => a + b) /
      points.length;
  final lonAverage =
      points.map((spot) => spot.longitude).reduce((a, b) => a + b) /
      points.length;
  return LatLng(latAverage, lonAverage);
}

double eventLocationZoom(Iterable<EventLocationSpot> spots) {
  final points = spots.toList(growable: false);
  if (points.length <= 1) return 15;

  final latitudes = points.map((spot) => spot.latitude);
  final longitudes = points.map((spot) => spot.longitude);
  final latSpan = latitudes.reduce(math.max) - latitudes.reduce(math.min);
  final lonSpan = longitudes.reduce(math.max) - longitudes.reduce(math.min);
  final span = math.max(latSpan, lonSpan);

  if (span < 0.0025) return 15;
  if (span < 0.01) return 14;
  if (span < 0.03) return 13;
  if (span < 0.08) return 12;
  if (span < 0.2) return 11;
  if (span < 0.5) return 10;
  if (span < 1.5) return 8.5;
  if (span < 4) return 7;
  return 5.5;
}

String eventLocationSummary(CivicEvent event) {
  final spots = eventLocationSpots(event.posts);
  if (spots.isEmpty || event.centerLat == null || event.centerLon == null) {
    return 'Hidden';
  }

  if (spots.length == 1) {
    return '${event.centerLat!.toStringAsFixed(4)}, ${event.centerLon!.toStringAsFixed(4)}';
  }

  return '${spots.length} spots · '
      '${event.centerLat!.toStringAsFixed(4)}, '
      '${event.centerLon!.toStringAsFixed(4)}';
}

enum EventTrendDirection { increasing, decreasing, steady }

class EventTrendBucket {
  const EventTrendBucket({
    required this.start,
    required this.end,
    required this.threadCount,
  });

  final DateTime start;
  final DateTime end;
  final int threadCount;
}

class EventTrendSnapshot {
  const EventTrendSnapshot({
    required this.buckets,
    required this.rangeStart,
    required this.rangeEnd,
    required this.totalThreadCount,
    required this.earlierThreadCount,
    required this.recentThreadCount,
    required this.direction,
  });

  final List<EventTrendBucket> buckets;
  final DateTime rangeStart;
  final DateTime rangeEnd;
  final int totalThreadCount;
  final int earlierThreadCount;
  final int recentThreadCount;
  final EventTrendDirection direction;

  int get maxBucketCount {
    if (buckets.isEmpty) return 0;
    return buckets.map((bucket) => bucket.threadCount).reduce(math.max);
  }

  String get directionLabel => switch (direction) {
    EventTrendDirection.increasing => 'Increasing',
    EventTrendDirection.decreasing => 'Decreasing',
    EventTrendDirection.steady => 'Stable',
  };

  Color get directionColor => switch (direction) {
    EventTrendDirection.increasing => SpotColors.success,
    EventTrendDirection.decreasing => SpotColors.danger,
    EventTrendDirection.steady => SpotColors.accent,
  };

  IconData get directionIcon => switch (direction) {
    EventTrendDirection.increasing => CupertinoIcons.arrow_up_right,
    EventTrendDirection.decreasing => CupertinoIcons.arrow_down_right,
    EventTrendDirection.steady => CupertinoIcons.arrow_left_right,
  };

  String get summaryText {
    if (totalThreadCount == 0) {
      return 'No thread activity yet for this category.';
    }
    if (totalThreadCount == 1) {
      return 'Only one thread so far. More activity will make the direction clearer.';
    }

    return switch (direction) {
      EventTrendDirection.increasing =>
        '$recentThreadCount recent threads vs $earlierThreadCount earlier. Activity is accelerating.',
      EventTrendDirection.decreasing =>
        '$recentThreadCount recent threads vs $earlierThreadCount earlier. Activity is cooling down.',
      EventTrendDirection.steady =>
        '$recentThreadCount recent threads vs $earlierThreadCount earlier. Activity is holding steady.',
    };
  }

  String get startAxisLabel => _formatEventTrendAxisLabel(
    rangeStart,
    rangeStart: rangeStart,
    rangeEnd: rangeEnd,
  );

  String get midAxisLabel => _formatEventTrendAxisLabel(
    rangeStart.add(
      Duration(
        milliseconds: rangeEnd.difference(rangeStart).inMilliseconds ~/ 2,
      ),
    ),
    rangeStart: rangeStart,
    rangeEnd: rangeEnd,
  );

  String get endAxisLabel => _formatEventTrendAxisLabel(
    rangeEnd,
    rangeStart: rangeStart,
    rangeEnd: rangeEnd,
  );
}

List<MediaPost> eventRootThreads(Iterable<MediaPost> posts) {
  final allPosts = posts.toList(growable: false);
  final ids = allPosts.map((post) => post.nostrEventId).toSet();
  final roots =
      allPosts
          .where(
            (post) => post.replyToId == null || !ids.contains(post.replyToId),
          )
          .toList(growable: false)
        ..sort((a, b) => a.capturedAt.compareTo(b.capturedAt));
  return roots;
}

EventTrendSnapshot buildEventTrendSnapshot(
  CivicEvent event, {
  int bucketCount = 6,
}) {
  final roots = eventRootThreads(event.posts);
  final effectiveBucketCount = math.max(4, bucketCount);

  final rangeStart = roots.isEmpty ? event.firstSeen : roots.first.capturedAt;
  var rangeEnd = roots.isEmpty ? event.firstSeen : roots.last.capturedAt;
  if (!rangeEnd.isAfter(rangeStart)) {
    rangeEnd = rangeStart.add(const Duration(hours: 1));
  }

  final totalRangeMs = math.max(
    1,
    rangeEnd.difference(rangeStart).inMilliseconds,
  );
  final bucketSpanMs = math.max(
    1,
    (totalRangeMs / effectiveBucketCount).ceil(),
  );
  final counts = List<int>.filled(effectiveBucketCount, 0);

  for (final root in roots) {
    final offsetMs = root.capturedAt.difference(rangeStart).inMilliseconds;
    final index = math.min(
      effectiveBucketCount - 1,
      math.max(0, offsetMs ~/ bucketSpanMs),
    );
    counts[index] += 1;
  }

  final buckets = List<EventTrendBucket>.generate(effectiveBucketCount, (
    index,
  ) {
    final start = rangeStart.add(Duration(milliseconds: index * bucketSpanMs));
    final end = index == effectiveBucketCount - 1
        ? rangeEnd
        : rangeStart.add(Duration(milliseconds: (index + 1) * bucketSpanMs));
    return EventTrendBucket(start: start, end: end, threadCount: counts[index]);
  }, growable: false);

  final splitIndex = effectiveBucketCount ~/ 2;
  final earlierThreadCount = counts
      .take(splitIndex)
      .fold<int>(0, (sum, value) => sum + value);
  final recentThreadCount = counts
      .skip(splitIndex)
      .fold<int>(0, (sum, value) => sum + value);

  return EventTrendSnapshot(
    buckets: buckets,
    rangeStart: rangeStart,
    rangeEnd: rangeEnd,
    totalThreadCount: roots.length,
    earlierThreadCount: earlierThreadCount,
    recentThreadCount: recentThreadCount,
    direction: _eventTrendDirection(
      earlierThreadCount: earlierThreadCount,
      recentThreadCount: recentThreadCount,
    ),
  );
}

EventTrendDirection _eventTrendDirection({
  required int earlierThreadCount,
  required int recentThreadCount,
}) {
  final delta = recentThreadCount - earlierThreadCount;
  final baseline = math.max(earlierThreadCount, 1);
  final changeRatio = delta / baseline;

  if (delta >= 1 && changeRatio >= 0.25) {
    return EventTrendDirection.increasing;
  }
  if (delta <= -1 && changeRatio <= -0.25) {
    return EventTrendDirection.decreasing;
  }
  return EventTrendDirection.steady;
}

String _formatEventTrendAxisLabel(
  DateTime value, {
  required DateTime rangeStart,
  required DateTime rangeEnd,
}) {
  final localValue = value.toLocal();
  final range = rangeEnd.difference(rangeStart);
  if (range <= const Duration(hours: 18)) {
    return DateFormat.Hm().format(localValue);
  }
  if (range <= const Duration(days: 3)) {
    return DateFormat('MMM d\nHH:mm').format(localValue);
  }
  return DateFormat('MMM d').format(localValue);
}

Witness? latestWitnessForUsers(
  Iterable<Witness> witnesses,
  Iterable<String> userIds,
) {
  final identities = userIds.where((id) => id.isNotEmpty).toSet();
  if (identities.isEmpty) return null;

  final matches =
      witnesses
          .where((witness) => identities.contains(witness.userId))
          .toList(growable: false)
        ..sort((a, b) => b.timestamp.compareTo(a.timestamp));

  return matches.isEmpty ? null : matches.first;
}

WitnessType? selectedWitnessTypeForUsers(
  Iterable<Witness> witnesses,
  Iterable<String> userIds,
) => latestWitnessForUsers(witnesses, userIds)?.type;

CivicEvent eventWithToggledWitness({
  required CivicEvent event,
  required Iterable<String> userIds,
  required String canonicalUserId,
  required WitnessType tappedType,
  DateTime? timestamp,
  double? lat,
  double? lon,
}) {
  final identities = userIds.where((id) => id.isNotEmpty).toSet();
  final currentType = selectedWitnessTypeForUsers(event.witnesses, identities);
  final nextType = currentType == tappedType ? null : tappedType;

  final retainedWitnesses = event.witnesses
      .where((witness) => !identities.contains(witness.userId))
      .toList(growable: true);

  if (nextType != null) {
    retainedWitnesses.add(
      Witness(
        id: 'local-${event.hashtag}-$canonicalUserId-${nextType.name}',
        eventId: event.hashtag,
        userId: canonicalUserId,
        type: nextType,
        lat: lat,
        lon: lon,
        timestamp: timestamp ?? DateTime.now().toUtc(),
        weight: 0.5,
      ),
    );
  }

  final updatedEvent = event.copyWith(witnesses: retainedWitnesses);
  final trust = const TrustService();
  final score = trust.computeEventTrust(updatedEvent, retainedWitnesses);
  final status = trust.statusFromScore(score, retainedWitnesses);

  return updatedEvent.copyWith(
    witnesses: retainedWitnesses,
    trustScore: score,
    status: status,
  );
}

class EventScreen extends StatefulWidget {
  const EventScreen({super.key, required this.event, required this.wallet});

  final CivicEvent event;
  final WalletModel wallet;

  @override
  State<EventScreen> createState() => _EventScreenState();
}

class _EventScreenState extends State<EventScreen> {
  late CivicEvent _event;
  bool _isFollowingTag = false;
  bool _isSubmittingWitness = false;

  @override
  void initState() {
    super.initState();
    _event = widget.event;
    _loadFollowState();
  }

  Future<void> _loadFollowState() async {
    await FollowService.instance.init();
    if (mounted) {
      setState(() {
        _isFollowingTag = FollowService.instance.isFollowingTag(_event.hashtag);
      });
    }
  }

  Future<void> _toggleFollowTag() async {
    if (_isFollowingTag) {
      await FollowService.instance.unfollowTag(_event.hashtag);
    } else {
      await FollowService.instance.followTag(_event.hashtag);
    }
    if (mounted) setState(() => _isFollowingTag = !_isFollowingTag);
  }

  Set<String> get _witnessActorIds {
    final identities = <String>{};
    if (widget.wallet.publicKeyHex.isNotEmpty) {
      identities.add(widget.wallet.publicKeyHex);
    }
    final authUserId = MetadataService.instance.client.auth.currentUser?.id;
    if (authUserId != null && authUserId.isNotEmpty) {
      identities.add(authUserId);
    }
    return identities;
  }

  String get _canonicalWitnessUserId {
    if (widget.wallet.publicKeyHex.isNotEmpty) {
      return widget.wallet.publicKeyHex;
    }
    return MetadataService.instance.client.auth.currentUser?.id ?? 'local-user';
  }

  Future<void> _submitWitness(WitnessType type) async {
    if (_isSubmittingWitness) return;

    final previousEvent = _event;
    final updatedEvent = eventWithToggledWitness(
      event: _event,
      userIds: _witnessActorIds,
      canonicalUserId: _canonicalWitnessUserId,
      tappedType: type,
      lat: _event.centerLat,
      lon: _event.centerLon,
    );

    setState(() {
      _isSubmittingWitness = true;
      _event = updatedEvent;
    });

    try {
      await MetadataService.instance.publishWitness(
        hashtag: _event.hashtag,
        witnessType: type.name,
        wallet: widget.wallet,
        lat: _event.centerLat,
        lon: _event.centerLon,
      );
    } catch (_) {
      if (mounted) {
        setState(() => _event = previousEvent);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not update witness signal.')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isSubmittingWitness = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final posts = _event.postsByNewest;

    return Scaffold(
      backgroundColor: SpotColors.bg,
      appBar: AppBar(
        backgroundColor: SpotColors.bg,
        title: Text('#${_event.hashtag}', style: SpotType.subheading),
        actions: [
          GestureDetector(
            onTap: _toggleFollowTag,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              margin: const EdgeInsets.only(right: SpotSpacing.lg),
              padding: const EdgeInsets.symmetric(
                horizontal: SpotSpacing.md,
                vertical: SpotSpacing.xs,
              ),
              decoration: BoxDecoration(
                color: _isFollowingTag
                    ? SpotColors.accent.withValues(alpha: 0.15)
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(SpotRadius.full),
                border: Border.all(
                  color: _isFollowingTag
                      ? SpotColors.accent
                      : SpotColors.border,
                  width: 0.5,
                ),
              ),
              child: Text(
                _isFollowingTag ? 'Following' : 'Follow',
                style: SpotType.label.copyWith(
                  color: _isFollowingTag
                      ? SpotColors.accent
                      : SpotColors.textSecondary,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ),
        ],
      ),
      body: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(child: _EventHeader(event: _event)),
          SliverToBoxAdapter(
            child: _WitnessSummary(
              event: _event,
              selectedType: selectedWitnessTypeForUsers(
                _event.witnesses,
                _witnessActorIds,
              ),
              isSubmitting: _isSubmittingWitness,
              onWitness: _submitWitness,
            ),
          ),
          SliverToBoxAdapter(child: _EventTrendPanel(event: _event)),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(
                SpotSpacing.lg,
                SpotSpacing.sm,
                SpotSpacing.lg,
                SpotSpacing.xs,
              ),
              child: Text('${posts.length} posts', style: SpotType.label),
            ),
          ),
          posts.isEmpty
              ? const SliverFillRemaining(
                  child: Center(
                    child: Text('No posts yet', style: SpotType.bodySecondary),
                  ),
                )
              : _ThreadSliver(posts: posts),
        ],
      ),
    );
  }
}

// ── Event header ───────────────────────────────────────────────────────────────

class _EventHeader extends StatelessWidget {
  const _EventHeader({required this.event});
  final CivicEvent event;

  @override
  Widget build(BuildContext context) {
    final df = DateFormat('MMM d, yyyy  HH:mm');

    return Container(
      margin: const EdgeInsets.all(SpotSpacing.lg),
      padding: const EdgeInsets.all(SpotSpacing.lg),
      decoration: SpotDecoration.cardBordered(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: Text(event.title, style: SpotType.subheading)),
              _TrustBadge(event: event),
            ],
          ),
          const SizedBox(height: SpotSpacing.lg),

          _StatRow(
            label: 'First seen',
            value: df.format(event.firstSeen.toLocal()),
          ),
          const SizedBox(height: SpotSpacing.xs),
          _StatRow(
            label: 'Participants',
            value: event.participantCount.toString(),
          ),
          const SizedBox(height: SpotSpacing.xs),
          _StatRow(label: 'Confidence', value: '${event.trustPercent}%'),
          const SizedBox(height: SpotSpacing.xs),
          _StatRow(label: 'Location', value: eventLocationSummary(event)),

          const SizedBox(height: SpotSpacing.lg),
          _EventLocationMap(event: event),
        ],
      ),
    );
  }
}

class _EventLocationMap extends StatelessWidget {
  const _EventLocationMap({required this.event});

  final CivicEvent event;

  static const _tileUrl =
      'https://basemaps.cartocdn.com/dark_all/{z}/{x}/{y}.png';

  @override
  Widget build(BuildContext context) {
    final spots = eventLocationSpots(event.posts);
    if (spots.isEmpty) {
      return Container(
        height: 108,
        decoration: BoxDecoration(
          color: SpotColors.bg,
          borderRadius: BorderRadius.circular(SpotRadius.sm),
          border: Border.all(color: SpotColors.border, width: 0.5),
        ),
        child: const Center(
          child: Text('Location hidden', style: SpotType.caption),
        ),
      );
    }

    final center = eventLocationCenter(spots);
    final zoom = eventLocationZoom(spots);
    final coordinates = spots
        .map((spot) => LatLng(spot.latitude, spot.longitude))
        .toList(growable: false);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          height: 184,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(SpotRadius.sm),
            child: Stack(
              children: [
                FlutterMap(
                  options: MapOptions(
                    initialCenter: center,
                    initialZoom: zoom,
                    initialCameraFit: coordinates.length > 1
                        ? CameraFit.coordinates(
                            coordinates: coordinates,
                            padding: const EdgeInsets.all(28),
                            maxZoom: 15,
                            minZoom: 5.5,
                          )
                        : null,
                    backgroundColor: SpotColors.bg,
                    interactionOptions: const InteractionOptions(
                      flags:
                          InteractiveFlag.drag |
                          InteractiveFlag.pinchZoom |
                          InteractiveFlag.doubleTapZoom,
                    ),
                  ),
                  children: [
                    TileLayer(
                      urlTemplate: _tileUrl,
                      userAgentPackageName: 'com.icyanstudio.spot',
                    ),
                    MarkerLayer(
                      markers: [
                        for (final spot in spots)
                          Marker(
                            point: LatLng(spot.latitude, spot.longitude),
                            width: 34,
                            height: 34,
                            child: Tooltip(
                              message: spot.label,
                              child: const _EventLocationMarker(),
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
                Positioned(
                  top: SpotSpacing.sm,
                  right: SpotSpacing.sm,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: SpotSpacing.sm,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: SpotColors.bg.withValues(alpha: 0.86),
                      borderRadius: BorderRadius.circular(SpotRadius.full),
                      border: Border.all(color: SpotColors.border, width: 0.5),
                    ),
                    child: Text(
                      '${spots.length} spot${spots.length == 1 ? '' : 's'}',
                      style: SpotType.caption.copyWith(
                        color: SpotColors.textPrimary,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: SpotSpacing.xs),
        Text(
          'Map tiles: OpenStreetMap / CARTO',
          style: SpotType.caption.copyWith(color: SpotColors.textTertiary),
        ),
      ],
    );
  }
}

class _EventLocationMarker extends StatelessWidget {
  const _EventLocationMarker();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Transform.translate(
        offset: const Offset(0, -4),
        child: Icon(
          Icons.location_on,
          color: SpotColors.accent,
          size: 26,
          shadows: [
            Shadow(color: SpotColors.bg.withValues(alpha: 0.7), blurRadius: 6),
          ],
        ),
      ),
    );
  }
}

class _EventTrendPanel extends StatelessWidget {
  const _EventTrendPanel({required this.event});

  final CivicEvent event;

  @override
  Widget build(BuildContext context) {
    final trend = buildEventTrendSnapshot(event);
    final yAxisMax = math.max(1, trend.maxBucketCount);
    final yAxisMid = math.max(1, (yAxisMax / 2).ceil());

    return Container(
      margin: const EdgeInsets.symmetric(
        horizontal: SpotSpacing.lg,
        vertical: SpotSpacing.xs,
      ),
      padding: const EdgeInsets.all(SpotSpacing.lg),
      decoration: SpotDecoration.cardBordered(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text('THREAD TREND', style: SpotType.label),
              const Spacer(),
              _TrendDirectionBadge(trend: trend),
            ],
          ),
          const SizedBox(height: SpotSpacing.sm),
          const Text('Thread Activity', style: SpotType.body),
          const SizedBox(height: SpotSpacing.xs),
          Text(trend.summaryText, style: SpotType.bodySecondary),
          const SizedBox(height: SpotSpacing.lg),
          SizedBox(
            height: 156,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SizedBox(
                  width: 28,
                  child: _TrendYAxis(
                    topLabel: yAxisMax.toString(),
                    middleLabel: yAxisMid.toString(),
                  ),
                ),
                const SizedBox(width: SpotSpacing.sm),
                Expanded(
                  child: CustomPaint(
                    painter: _EventTrendChartPainter(trend: trend),
                    child: const SizedBox.expand(),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: SpotSpacing.sm),
          Padding(
            padding: const EdgeInsets.only(left: 36),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                _TrendAxisLabel(
                  label: trend.startAxisLabel,
                  alignment: TextAlign.left,
                ),
                _TrendAxisLabel(
                  label: trend.midAxisLabel,
                  alignment: TextAlign.center,
                ),
                _TrendAxisLabel(
                  label: trend.endAxisLabel,
                  alignment: TextAlign.right,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _TrendDirectionBadge extends StatelessWidget {
  const _TrendDirectionBadge({required this.trend});

  final EventTrendSnapshot trend;

  @override
  Widget build(BuildContext context) {
    final color = trend.directionColor;
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: SpotSpacing.sm,
        vertical: 3,
      ),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(SpotRadius.full),
        border: Border.all(color: color.withValues(alpha: 0.4), width: 0.5),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(trend.directionIcon, size: 12, color: color),
          const SizedBox(width: 4),
          Text(
            trend.directionLabel,
            style: SpotType.caption.copyWith(color: color),
          ),
        ],
      ),
    );
  }
}

class _TrendYAxis extends StatelessWidget {
  const _TrendYAxis({required this.topLabel, required this.middleLabel});

  final String topLabel;
  final String middleLabel;

  @override
  Widget build(BuildContext context) {
    final style = SpotType.caption.copyWith(color: SpotColors.textSecondary);
    return Column(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Text(topLabel, style: style),
        Text(middleLabel, style: style),
        Text('0', style: style),
      ],
    );
  }
}

class _TrendAxisLabel extends StatelessWidget {
  const _TrendAxisLabel({required this.label, required this.alignment});

  final String label;
  final TextAlign alignment;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Text(
        label,
        textAlign: alignment,
        style: SpotType.caption.copyWith(color: SpotColors.textSecondary),
      ),
    );
  }
}

class _EventTrendChartPainter extends CustomPainter {
  const _EventTrendChartPainter({required this.trend});

  final EventTrendSnapshot trend;

  @override
  void paint(Canvas canvas, Size size) {
    final chartTop = 6.0;
    final chartBottom = size.height - 8;
    final chartHeight = chartBottom - chartTop;
    final maxCount = math.max(1, trend.maxBucketCount);

    final gridPaint = Paint()
      ..color = SpotColors.border.withValues(alpha: 0.9)
      ..strokeWidth = 0.5;
    final baselinePaint = Paint()
      ..color = SpotColors.border
      ..strokeWidth = 1;

    for (final fraction in [0.0, 0.5, 1.0]) {
      final y = chartBottom - (chartHeight * fraction);
      canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
    }

    final bucketCount = trend.buckets.length;
    if (bucketCount == 0) return;

    final gap = 6.0;
    final barWidth = math.max(
      8.0,
      (size.width - ((bucketCount - 1) * gap)) / bucketCount,
    );
    final totalBarWidth = (barWidth * bucketCount) + ((bucketCount - 1) * gap);
    final startX = math.max(0.0, (size.width - totalBarWidth) / 2);
    final color = trend.directionColor;

    final trendPath = ui.Path();
    for (int index = 0; index < bucketCount; index++) {
      final bucket = trend.buckets[index];
      final ratio = bucket.threadCount / maxCount;
      final barHeight = math.max(
        bucket.threadCount > 0 ? 4.0 : 0.0,
        chartHeight * ratio,
      );
      final x = startX + (index * (barWidth + gap));
      final top = chartBottom - barHeight;

      final rect = RRect.fromRectAndRadius(
        Rect.fromLTWH(x, top, barWidth, barHeight),
        const Radius.circular(4),
      );
      final barPaint = Paint()
        ..color = color.withValues(
          alpha: 0.35 + (0.45 * ((index + 1) / bucketCount)),
        );
      canvas.drawRRect(rect, barPaint);

      final point = Offset(x + (barWidth / 2), top);
      if (index == 0) {
        trendPath.moveTo(point.dx, point.dy);
      } else {
        trendPath.lineTo(point.dx, point.dy);
      }
    }

    canvas.drawLine(
      Offset(0, chartBottom),
      Offset(size.width, chartBottom),
      baselinePaint,
    );
    canvas.drawPath(
      trendPath,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.4,
    );
  }

  @override
  bool shouldRepaint(covariant _EventTrendChartPainter oldDelegate) =>
      oldDelegate.trend != trend;
}

class _StatRow extends StatelessWidget {
  const _StatRow({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        SizedBox(width: 90, child: Text(label, style: SpotType.label)),
        Expanded(
          child: Text(
            value,
            style: SpotType.bodySecondary,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}

// ── Thread sliver ──────────────────────────────────────────────────────────────

/// Renders [posts] as a depth-first thread tree (roots + nested replies).
class _ThreadSliver extends StatelessWidget {
  const _ThreadSliver({required this.posts});
  final List<MediaPost> posts;

  /// Returns posts in depth-first order with their nesting depth.
  static List<({MediaPost post, int depth})> _flatten(List<MediaPost> all) {
    final ids = {for (final p in all) p.nostrEventId};
    final roots =
        all
            .where((p) => p.replyToId == null || !ids.contains(p.replyToId))
            .toList()
          ..sort((a, b) => a.capturedAt.compareTo(b.capturedAt));

    final out = <({MediaPost post, int depth})>[];
    void visit(MediaPost p, int depth) {
      out.add((post: p, depth: depth));
      final replies = all.where((r) => r.replyToId == p.nostrEventId).toList()
        ..sort((a, b) => a.capturedAt.compareTo(b.capturedAt));
      for (final r in replies) {
        visit(r, depth + 1);
      }
    }

    for (final root in roots) {
      visit(root, 0);
    }
    return out;
  }

  @override
  Widget build(BuildContext context) {
    final items = _flatten(posts);
    return SliverList(
      delegate: SliverChildBuilderDelegate((ctx, i) {
        final (:post, :depth) = items[i];
        return _ThreadPostCard(post: post, depth: depth);
      }, childCount: items.length),
    );
  }
}

// ── Thread post card ────────────────────────────────────────────────────────────

class _ThreadPostCard extends StatelessWidget {
  const _ThreadPostCard({required this.post, required this.depth});
  final MediaPost post;
  final int depth;

  @override
  Widget build(BuildContext context) {
    final df = DateFormat('MMM d  HH:mm');
    final shortKey = post.pubkey.length > 12
        ? '${post.pubkey.substring(0, 8)}…'
        : post.pubkey;
    // Cap visible indent at 4 levels
    final indent = depth.clamp(0, 4) * 18.0;

    return Container(
      margin: EdgeInsets.fromLTRB(
        SpotSpacing.lg + indent,
        0,
        SpotSpacing.lg,
        4,
      ),
      decoration: depth == 0
          ? SpotDecoration.card()
          : BoxDecoration(
              color: SpotColors.surface,
              borderRadius: BorderRadius.circular(SpotRadius.sm),
              border: Border(
                left: BorderSide(
                  color: SpotColors.accent.withValues(alpha: 0.35),
                  width: 2,
                ),
              ),
            ),
      child: Row(
        children: [
          // Thumbnail area
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              color: SpotColors.bg,
              borderRadius: depth == 0
                  ? const BorderRadius.only(
                      topLeft: Radius.circular(SpotRadius.sm),
                      bottomLeft: Radius.circular(SpotRadius.sm),
                    )
                  : null,
            ),
            child: Center(
              child: Icon(
                post.isDangerMode
                    ? CupertinoIcons.shield
                    : CupertinoIcons.photo,
                color: post.isDangerMode
                    ? SpotColors.danger.withAlpha(160)
                    : SpotColors.overlay,
                size: 20,
              ),
            ),
          ),
          const SizedBox(width: SpotSpacing.sm),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: SpotSpacing.sm),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (depth > 0)
                    Row(
                      children: [
                        const Icon(
                          CupertinoIcons.arrow_turn_up_left,
                          size: 10,
                          color: SpotColors.textTertiary,
                        ),
                        const SizedBox(width: 3),
                        Text('reply', style: SpotType.caption),
                      ],
                    ),
                  if (post.isDangerMode)
                    Container(
                      margin: const EdgeInsets.only(bottom: 3),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 5,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: SpotColors.dangerSubtle,
                        borderRadius: BorderRadius.circular(SpotRadius.xs),
                      ),
                      child: Text(
                        'Protected',
                        style: SpotType.label.copyWith(
                          color: SpotColors.danger,
                        ),
                      ),
                    ),
                  Text(shortKey, style: SpotType.mono),
                  const SizedBox(height: 2),
                  Text(
                    df.format(post.capturedAt.toLocal()),
                    style: SpotType.caption,
                  ),
                  if (post.caption != null) ...[
                    const SizedBox(height: 3),
                    Text(
                      post.caption!,
                      style: SpotType.bodySecondary,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ],
              ),
            ),
          ),
          const Icon(
            CupertinoIcons.chevron_right,
            color: SpotColors.overlay,
            size: 14,
          ),
          const SizedBox(width: SpotSpacing.xs),
        ],
      ),
    );
  }
}

// ── Trust badge ────────────────────────────────────────────────────────────────

/// Confidence-level indicator (🟢 High / 🟡 Unverified / 🔴 Conflicted).
class _TrustBadge extends StatelessWidget {
  const _TrustBadge({required this.event});
  final CivicEvent event;

  @override
  Widget build(BuildContext context) {
    final (label, color) = switch (event.status) {
      EventStatus.highConfidence => ('● High', SpotColors.success),
      EventStatus.conflicted => ('● Conflicted', SpotColors.danger),
      EventStatus.unverified => ('● Unverified', SpotColors.warning),
    };

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: SpotSpacing.sm,
        vertical: 3,
      ),
      decoration: BoxDecoration(
        color: color.withAlpha(25),
        borderRadius: BorderRadius.circular(SpotRadius.xs),
        border: Border.all(color: color.withAlpha(80), width: 0.5),
      ),
      child: Text(
        label,
        style: SpotType.label.copyWith(color: color, letterSpacing: 0.5),
      ),
    );
  }
}

// ── Witness summary ────────────────────────────────────────────────────────────

/// Shows seen / confirm / deny counts and lets the user submit a signal.
class _WitnessSummary extends StatelessWidget {
  const _WitnessSummary({
    required this.event,
    this.selectedType,
    this.isSubmitting = false,
    this.onWitness,
  });

  final CivicEvent event;
  final WitnessType? selectedType;
  final bool isSubmitting;

  /// Called with the witness type string when user taps a button.
  final void Function(WitnessType type)? onWitness;

  @override
  Widget build(BuildContext context) {
    final totalWitnesses =
        event.seenCount + event.confirmCount + event.denyCount;

    return Container(
      margin: const EdgeInsets.symmetric(
        horizontal: SpotSpacing.lg,
        vertical: SpotSpacing.xs,
      ),
      padding: const EdgeInsets.all(SpotSpacing.lg),
      decoration: SpotDecoration.cardBordered(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text('WITNESSES', style: SpotType.label),
              const Spacer(),
              Text('$totalWitnesses total', style: SpotType.caption),
            ],
          ),
          if (onWitness != null) ...[
            const SizedBox(height: SpotSpacing.md),
            Row(
              children: [
                _WitnessButton(
                  label: 'Seen',
                  icon: CupertinoIcons.eye,
                  count: event.seenCount,
                  isSelected: selectedType == WitnessType.seen,
                  isSubmitting: isSubmitting,
                  color: SpotColors.textSecondary,
                  onTap: () => onWitness!(WitnessType.seen),
                ),
                const SizedBox(width: SpotSpacing.sm),
                _WitnessButton(
                  label: 'Confirm',
                  icon: CupertinoIcons.checkmark_circle,
                  count: event.confirmCount,
                  isSelected: selectedType == WitnessType.confirm,
                  isSubmitting: isSubmitting,
                  color: SpotColors.success,
                  onTap: () => onWitness!(WitnessType.confirm),
                ),
                const SizedBox(width: SpotSpacing.sm),
                _WitnessButton(
                  label: 'Deny',
                  icon: CupertinoIcons.xmark_circle,
                  count: event.denyCount,
                  isSelected: selectedType == WitnessType.deny,
                  isSubmitting: isSubmitting,
                  color: SpotColors.danger,
                  onTap: () => onWitness!(WitnessType.deny),
                ),
              ],
            ),
            if (selectedType != null) ...[
              const SizedBox(height: SpotSpacing.sm),
              Text(
                'Tap your selected signal again to remove it.',
                style: SpotType.caption.copyWith(
                  color: SpotColors.textSecondary,
                ),
              ),
            ],
          ],
        ],
      ),
    );
  }
}

class _WitnessButton extends StatelessWidget {
  const _WitnessButton({
    required this.label,
    required this.icon,
    required this.count,
    required this.isSelected,
    required this.isSubmitting,
    required this.color,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final int count;
  final bool isSelected;
  final bool isSubmitting;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Expanded(
    child: GestureDetector(
      onTap: isSubmitting ? null : onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(vertical: SpotSpacing.sm),
        decoration: BoxDecoration(
          color: isSelected
              ? color.withValues(alpha: 0.22)
              : color.withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(SpotRadius.sm),
          border: Border.all(
            color: isSelected
                ? color.withValues(alpha: 0.85)
                : color.withValues(alpha: 0.35),
            width: isSelected ? 1 : 0.5,
          ),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: color.withValues(alpha: 0.18),
                    blurRadius: 12,
                    spreadRadius: 0.5,
                  ),
                ]
              : const [],
        ),
        child: Column(
          children: [
            Icon(icon, color: color, size: 16),
            const SizedBox(height: 3),
            Text(label, style: SpotType.caption.copyWith(color: color)),
            const SizedBox(height: 4),
            Text(
              count.toString(),
              style: SpotType.subheading.copyWith(color: color),
            ),
          ],
        ),
      ),
    ),
  );
}
