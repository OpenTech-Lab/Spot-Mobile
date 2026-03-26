import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'package:mobile/features/metadata/metadata_service.dart';
import 'package:mobile/models/event_model.dart';
import 'package:mobile/models/media_post.dart';
import 'package:mobile/models/wallet_model.dart';
import 'package:mobile/services/follow_service.dart';
import 'package:mobile/theme/spot_theme.dart';

/// Event detail — wiki-like timeline for a [CivicEvent] with EBES trust data.
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

  Future<void> _submitWitness(String type) async {
    try {
      await MetadataService.instance.publishWitness(
        hashtag: _event.hashtag,
        witnessType: type,
        wallet: widget.wallet,
      );
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Signal "$type" sent.')));
      }
    } catch (_) {}
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
            child: _WitnessSummary(event: _event, onWitness: _submitWitness),
          ),
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

          if (event.centerLat != null) ...[
            const SizedBox(height: SpotSpacing.xs),
            _StatRow(
              label: 'Location',
              value:
                  '${event.centerLat!.toStringAsFixed(4)}, '
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
                        const Icon(
                          CupertinoIcons.location,
                          color: SpotColors.textTertiary,
                          size: 20,
                        ),
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
  const _WitnessSummary({required this.event, this.onWitness});

  final CivicEvent event;

  /// Called with the witness type string when user taps a button.
  final void Function(String type)? onWitness;

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
          const SizedBox(height: SpotSpacing.md),
          Row(
            children: [
              _WitnessCount(
                label: 'Seen',
                count: event.seenCount,
                color: SpotColors.textSecondary,
              ),
              const SizedBox(width: SpotSpacing.md),
              _WitnessCount(
                label: 'Confirm',
                count: event.confirmCount,
                color: SpotColors.success,
              ),
              const SizedBox(width: SpotSpacing.md),
              _WitnessCount(
                label: 'Deny',
                count: event.denyCount,
                color: SpotColors.danger,
              ),
            ],
          ),
          if (onWitness != null) ...[
            const SizedBox(height: SpotSpacing.lg),
            Text('SUBMIT SIGNAL', style: SpotType.label),
            const SizedBox(height: SpotSpacing.sm),
            Row(
              children: [
                _WitnessButton(
                  label: 'Seen',
                  icon: CupertinoIcons.eye,
                  color: SpotColors.textSecondary,
                  onTap: () => onWitness!('seen'),
                ),
                const SizedBox(width: SpotSpacing.sm),
                _WitnessButton(
                  label: 'Confirm',
                  icon: CupertinoIcons.checkmark_circle,
                  color: SpotColors.success,
                  onTap: () => onWitness!('confirm'),
                ),
                const SizedBox(width: SpotSpacing.sm),
                _WitnessButton(
                  label: 'Deny',
                  icon: CupertinoIcons.xmark_circle,
                  color: SpotColors.danger,
                  onTap: () => onWitness!('deny'),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _WitnessCount extends StatelessWidget {
  const _WitnessCount({
    required this.label,
    required this.count,
    required this.color,
  });

  final String label;
  final int count;
  final Color color;

  @override
  Widget build(BuildContext context) => Column(
    children: [
      Text(count.toString(), style: SpotType.subheading.copyWith(color: color)),
      Text(label, style: SpotType.caption),
    ],
  );
}

class _WitnessButton extends StatelessWidget {
  const _WitnessButton({
    required this.label,
    required this.icon,
    required this.color,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Expanded(
    child: GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: SpotSpacing.sm),
        decoration: BoxDecoration(
          color: color.withAlpha(20),
          borderRadius: BorderRadius.circular(SpotRadius.sm),
          border: Border.all(color: color.withAlpha(60), width: 0.5),
        ),
        child: Column(
          children: [
            Icon(icon, color: color, size: 16),
            const SizedBox(height: 3),
            Text(label, style: SpotType.caption.copyWith(color: color)),
          ],
        ),
      ),
    ),
  );
}
