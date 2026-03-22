import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'package:mobile/models/event_model.dart';
import 'package:mobile/models/media_post.dart';
import 'package:mobile/theme/spot_theme.dart';

/// Event detail — wiki-like timeline for a [CivicEvent].
class EventScreen extends StatelessWidget {
  const EventScreen({super.key, required this.event});

  final CivicEvent event;

  @override
  Widget build(BuildContext context) {
    final posts = event.postsByNewest;

    return Scaffold(
      backgroundColor: SpotColors.bg,
      appBar: AppBar(
        backgroundColor: SpotColors.bg,
        title: Text('#${event.hashtag}', style: SpotType.subheading),
        actions: [
          Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: SpotSpacing.lg,
              vertical: SpotSpacing.sm,
            ),
            child: Chip(
              label: Text('${event.participantCount} contributors'),
            ),
          ),
        ],
      ),
      body: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(child: _EventHeader(event: event)),

          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(
                SpotSpacing.lg, SpotSpacing.sm,
                SpotSpacing.lg, SpotSpacing.xs,
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
              : SliverList(
                  delegate: SliverChildBuilderDelegate(
                    (ctx, i) => _PostCard(post: posts[i]),
                    childCount: posts.length,
                  ),
                ),
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
          Text(event.title, style: SpotType.subheading),
          const SizedBox(height: SpotSpacing.lg),

          _StatRow(label: 'First seen',     value: df.format(event.firstSeen.toLocal())),
          const SizedBox(height: SpotSpacing.xs),
          _StatRow(label: 'Participants',   value: event.participantCount.toString()),

          if (event.centerLat != null) ...[
            const SizedBox(height: SpotSpacing.xs),
            _StatRow(
              label: 'Location',
              value: '${event.centerLat!.toStringAsFixed(4)}, '
                  '${event.centerLon!.toStringAsFixed(4)}',
            ),
          ] else ...[
            const SizedBox(height: SpotSpacing.xs),
            const _StatRow(label: 'Location', value: 'Hidden'),
          ],

          const SizedBox(height: SpotSpacing.lg),

          // Location card (placeholder for flutter_map integration)
          Container(
            height: 100,
            decoration: BoxDecoration(
              color: SpotColors.bg,
              borderRadius: BorderRadius.circular(SpotRadius.sm),
              border: Border.all(color: SpotColors.border, width: 0.5),
            ),
            child: Center(
              child: event.centerLat != null
                  ? Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.location_on_outlined,
                            color: SpotColors.textTertiary, size: 20),
                        const SizedBox(height: SpotSpacing.xs),
                        Text(
                          '${event.centerLat!.toStringAsFixed(4)}, '
                          '${event.centerLon!.toStringAsFixed(4)}',
                          style: SpotType.caption,
                        ),
                      ],
                    )
                  : const Text('Location hidden', style: SpotType.caption),
            ),
          ),
        ],
      ),
    );
  }
}

class _StatRow extends StatelessWidget {
  const _StatRow({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        SizedBox(
          width: 90,
          child: Text(label, style: SpotType.label),
        ),
        Expanded(
          child: Text(value, style: SpotType.bodySecondary, overflow: TextOverflow.ellipsis),
        ),
      ],
    );
  }
}

// ── Post card ──────────────────────────────────────────────────────────────────

class _PostCard extends StatelessWidget {
  const _PostCard({required this.post});
  final MediaPost post;

  @override
  Widget build(BuildContext context) {
    final df = DateFormat('MMM d  HH:mm');
    final shortKey = post.pubkey.length > 12
        ? '${post.pubkey.substring(0, 8)}…'
        : post.pubkey;

    return Container(
      margin: const EdgeInsets.symmetric(
        horizontal: SpotSpacing.lg,
        vertical: 4,
      ),
      decoration: SpotDecoration.card(),
      child: Row(
        children: [
          // Thumbnail area
          Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(
              color: SpotColors.bg,
              borderRadius: const BorderRadius.only(
                topLeft:    Radius.circular(SpotRadius.sm),
                bottomLeft: Radius.circular(SpotRadius.sm),
              ),
            ),
            child: Center(
              child: Icon(
                post.isDangerMode
                    ? Icons.shield_outlined
                    : Icons.image_outlined,
                color: post.isDangerMode
                    ? SpotColors.danger.withAlpha(160)
                    : SpotColors.overlay,
                size: 22,
              ),
            ),
          ),

          const SizedBox(width: SpotSpacing.md),

          // Details
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: SpotSpacing.md),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (post.isDangerMode)
                    Container(
                      margin: const EdgeInsets.only(bottom: 4),
                      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                      decoration: BoxDecoration(
                        color: SpotColors.dangerSubtle,
                        borderRadius: BorderRadius.circular(SpotRadius.xs),
                      ),
                      child: Text(
                        'Protected',
                        style: SpotType.label.copyWith(color: SpotColors.danger),
                      ),
                    ),
                  Text(shortKey, style: SpotType.mono),
                  const SizedBox(height: 3),
                  Text(df.format(post.capturedAt.toLocal()), style: SpotType.caption),
                  const SizedBox(height: SpotSpacing.xs),
                  Row(
                    children: [
                      Icon(
                        post.hasGps ? Icons.gps_fixed : Icons.gps_off,
                        color: post.hasGps
                            ? SpotColors.success.withAlpha(160)
                            : SpotColors.textTertiary,
                        size: 11,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        post.hasGps
                            ? '${post.latitude!.toStringAsFixed(3)}, '
                              '${post.longitude!.toStringAsFixed(3)}'
                            : 'Hidden',
                        style: SpotType.caption,
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),

          const Icon(Icons.chevron_right, color: SpotColors.overlay, size: 16),
          const SizedBox(width: SpotSpacing.sm),
        ],
      ),
    );
  }
}
