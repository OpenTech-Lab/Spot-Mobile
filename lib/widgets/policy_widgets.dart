import 'package:flutter/material.dart';

import 'package:mobile/theme/spot_theme.dart';

class PolicyMeta extends StatelessWidget {
  const PolicyMeta({super.key, required this.date});

  final String date;

  @override
  Widget build(BuildContext context) {
    return Text(date, style: SpotType.bodySecondary);
  }
}

class PolicySection extends StatelessWidget {
  const PolicySection({super.key, required this.heading, required this.body});

  final String heading;
  final String body;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: SpotSpacing.xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(heading, style: SpotType.subheading),
          const SizedBox(height: SpotSpacing.sm),
          Text(body, style: SpotType.bodySecondary),
        ],
      ),
    );
  }
}
