import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'package:mobile/theme/spot_theme.dart';

class ProfileStatsRow extends StatelessWidget {
  const ProfileStatsRow({
    super.key,
    required this.postCount,
    required this.followingCount,
    required this.followerCount,
    this.joinedAt,
    this.lastThreadAt,
    this.lastReplyAt,
  });

  final int postCount;
  final int followingCount;
  final int followerCount;
  final DateTime? joinedAt;
  final DateTime? lastThreadAt;
  final DateTime? lastReplyAt;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            Expanded(
              child: _ProfileStat(value: '$postCount', label: 'Posts'),
            ),
            Expanded(
              child: _ProfileStat(value: '$followingCount', label: 'Following'),
            ),
            Expanded(
              child: _ProfileStat(value: '$followerCount', label: 'Followers'),
            ),
          ],
        ),
        const SizedBox(height: SpotSpacing.md),
        Row(
          children: [
            Expanded(
              child: _ProfileStat(
                value: _formatDate(joinedAt, empty: '-'),
                label: 'Joined',
                compact: true,
              ),
            ),
            Expanded(
              child: _ProfileStat(
                value: _formatDate(lastThreadAt, empty: '-'),
                label: 'Thread',
                compact: true,
              ),
            ),
            Expanded(
              child: _ProfileStat(
                value: _formatDate(lastReplyAt, empty: '-'),
                label: 'Reply',
                compact: true,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

String _formatDate(DateTime? value, {required String empty}) {
  if (value == null) return empty;
  return DateFormat('yyyy/MM/dd').format(value.toLocal());
}

class _ProfileStat extends StatelessWidget {
  const _ProfileStat({
    required this.value,
    required this.label,
    this.compact = false,
  });

  final String value;
  final String label;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final valueStyle = compact
        ? SpotType.caption.copyWith(
            color: SpotColors.textPrimary,
            fontWeight: FontWeight.w600,
          )
        : SpotType.subheading;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(value, style: valueStyle, textAlign: TextAlign.center),
        const SizedBox(height: 2),
        Text(label, style: SpotType.caption, textAlign: TextAlign.center),
      ],
    );
  }
}
