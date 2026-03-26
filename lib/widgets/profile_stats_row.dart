import 'package:flutter/material.dart';

import 'package:mobile/theme/spot_theme.dart';

class ProfileStatsRow extends StatelessWidget {
  const ProfileStatsRow({
    super.key,
    required this.postCount,
    required this.followingCount,
    required this.followerCount,
  });

  final int postCount;
  final int followingCount;
  final int followerCount;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: _ProfileStat(value: postCount, label: 'Posts'),
        ),
        Expanded(
          child: _ProfileStat(value: followingCount, label: 'Following'),
        ),
        Expanded(
          child: _ProfileStat(value: followerCount, label: 'Followers'),
        ),
      ],
    );
  }
}

class _ProfileStat extends StatelessWidget {
  const _ProfileStat({required this.value, required this.label});

  final int value;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text('$value', style: SpotType.subheading),
        const SizedBox(height: 2),
        Text(label, style: SpotType.caption, textAlign: TextAlign.center),
      ],
    );
  }
}
