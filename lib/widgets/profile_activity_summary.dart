import 'package:flutter/cupertino.dart';
import 'package:intl/intl.dart';

import 'package:mobile/models/media_post.dart';
import 'package:mobile/services/geo_lookup.dart';
import 'package:mobile/theme/spot_theme.dart';

class ProfileLocationStat {
  const ProfileLocationStat({required this.label, required this.count});

  final String label;
  final int count;
}

class ProfileActivitySummary {
  const ProfileActivitySummary({
    required this.accountCreatedAt,
    required this.lastThreadAt,
    required this.lastReplyAt,
    required this.topLocations,
  });

  final DateTime? accountCreatedAt;
  final DateTime? lastThreadAt;
  final DateTime? lastReplyAt;
  final List<ProfileLocationStat> topLocations;
}

ProfileActivitySummary buildProfileActivitySummary({
  required Iterable<MediaPost> posts,
  DateTime? accountCreatedAt,
}) {
  final allPosts = posts.toList(growable: false);
  final threads = allPosts.where((post) => post.replyToId == null).toList()
    ..sort((a, b) => b.capturedAt.compareTo(a.capturedAt));
  final replies = allPosts.where((post) => post.replyToId != null).toList()
    ..sort((a, b) => b.capturedAt.compareTo(a.capturedAt));
  final counts = <String, int>{};

  for (final post in allPosts) {
    final label = _aggregateLocationLabelForPost(post);
    if (label == null) continue;
    counts.update(label, (value) => value + 1, ifAbsent: () => 1);
  }

  final topLocations =
      counts.entries
          .map(
            (entry) =>
                ProfileLocationStat(label: entry.key, count: entry.value),
          )
          .toList()
        ..sort((a, b) {
          final byCount = b.count.compareTo(a.count);
          if (byCount != 0) return byCount;
          return a.label.compareTo(b.label);
        });

  return ProfileActivitySummary(
    accountCreatedAt: accountCreatedAt,
    lastThreadAt: threads.isEmpty ? null : threads.first.capturedAt,
    lastReplyAt: replies.isEmpty ? null : replies.first.capturedAt,
    topLocations: topLocations.take(3).toList(growable: false),
  );
}

String? _aggregateLocationLabelForPost(MediaPost post) {
  if (post.isVirtual || !post.hasGps) return null;

  final geo = GeoLookup.instance.nearest(post.latitude!, post.longitude!);
  if (geo != null) return '${geo.country}/${geo.city}';

  return '${post.latitude!.toStringAsFixed(1)}, ${post.longitude!.toStringAsFixed(1)}';
}

class ProfileActivitySummaryCard extends StatelessWidget {
  const ProfileActivitySummaryCard({super.key, required this.summary});

  final ProfileActivitySummary summary;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(SpotSpacing.md),
      decoration: BoxDecoration(
        color: SpotColors.surfaceHigh,
        borderRadius: BorderRadius.circular(SpotRadius.md),
        border: Border.all(color: SpotColors.border, width: 0.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _ProfileMetaRow(
            icon: CupertinoIcons.calendar,
            label: 'Account created',
            value: _formatDateTime(summary.accountCreatedAt),
          ),
          const SizedBox(height: SpotSpacing.sm),
          _ProfileMetaRow(
            icon: CupertinoIcons.text_bubble,
            label: 'Last thread',
            value: _formatDateTime(
              summary.lastThreadAt,
              empty: 'No threads yet',
            ),
          ),
          const SizedBox(height: SpotSpacing.sm),
          _ProfileMetaRow(
            icon: CupertinoIcons.arrow_turn_up_left,
            label: 'Last reply',
            value: _formatDateTime(
              summary.lastReplyAt,
              empty: 'No replies yet',
            ),
          ),
          const SizedBox(height: SpotSpacing.md),
          Text('Top locations', style: SpotType.caption),
          const SizedBox(height: SpotSpacing.sm),
          if (summary.topLocations.isEmpty)
            Text('No public locations yet', style: SpotType.bodySecondary)
          else
            Wrap(
              spacing: SpotSpacing.sm,
              runSpacing: SpotSpacing.sm,
              children: [
                for (final location in summary.topLocations)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: SpotSpacing.sm,
                      vertical: SpotSpacing.xs,
                    ),
                    decoration: BoxDecoration(
                      color: SpotColors.bg,
                      borderRadius: BorderRadius.circular(SpotRadius.sm),
                      border: Border.all(color: SpotColors.border, width: 0.5),
                    ),
                    child: Text(
                      '${location.label} · ${location.count}',
                      style: SpotType.caption,
                    ),
                  ),
              ],
            ),
        ],
      ),
    );
  }
}

class _ProfileMetaRow extends StatelessWidget {
  const _ProfileMetaRow({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 14, color: SpotColors.textTertiary),
        const SizedBox(width: SpotSpacing.sm),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: SpotType.caption),
              const SizedBox(height: 2),
              Text(value, style: SpotType.bodySecondary),
            ],
          ),
        ),
      ],
    );
  }
}

String _formatDateTime(DateTime? value, {String empty = 'Unknown'}) {
  if (value == null) return empty;
  return DateFormat('MMM d, yyyy  HH:mm').format(value.toLocal());
}
