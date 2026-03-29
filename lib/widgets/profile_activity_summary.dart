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

class ProfileActivitySummaryChips extends StatelessWidget {
  const ProfileActivitySummaryChips({super.key, required this.summary});

  final ProfileActivitySummary summary;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: SpotSpacing.sm,
      runSpacing: SpotSpacing.sm,
      children: [
        _ProfileSummaryChip(
          label: 'Created',
          value: _formatDateTime(summary.accountCreatedAt),
        ),
        _ProfileSummaryChip(
          label: 'Last thread',
          value: _formatDateTime(summary.lastThreadAt, empty: 'No threads yet'),
        ),
        _ProfileSummaryChip(
          label: 'Last reply',
          value: _formatDateTime(summary.lastReplyAt, empty: 'No replies yet'),
        ),
        if (summary.topLocations.isEmpty)
          const _ProfileSummaryChip(
            label: 'Locations',
            value: 'No public locations yet',
            isLocation: true,
          )
        else
          for (var i = 0; i < summary.topLocations.length; i++)
            _ProfileSummaryChip(
              label: 'Top ${i + 1}',
              value:
                  '${summary.topLocations[i].label} · ${summary.topLocations[i].count}',
              isLocation: true,
            ),
      ],
    );
  }
}

class _ProfileSummaryChip extends StatelessWidget {
  const _ProfileSummaryChip({
    required this.label,
    required this.value,
    this.isLocation = false,
  });

  final String label;
  final String value;
  final bool isLocation;

  @override
  Widget build(BuildContext context) {
    final backgroundColor = isLocation
        ? SpotColors.accentSubtle
        : SpotColors.surfaceHigh;
    final borderColor = isLocation
        ? SpotColors.accent.withAlpha(60)
        : SpotColors.border;
    final labelColor = isLocation ? SpotColors.accent : SpotColors.textTertiary;
    final valueColor = isLocation ? SpotColors.accent : SpotColors.textPrimary;

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: SpotSpacing.md,
        vertical: SpotSpacing.xs,
      ),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(SpotRadius.full),
        border: Border.all(color: borderColor, width: 0.5),
      ),
      child: Text.rich(
        TextSpan(
          children: [
            TextSpan(
              text: '$label · ',
              style: SpotType.caption.copyWith(color: labelColor),
            ),
            TextSpan(
              text: value,
              style: SpotType.bodySecondary.copyWith(
                color: valueColor,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

String _formatDateTime(DateTime? value, {String empty = 'Unknown'}) {
  if (value == null) return empty;
  return DateFormat('MMM d, yyyy  HH:mm').format(value.toLocal());
}
