import 'package:flutter/material.dart';

import 'package:mobile/theme/spot_theme.dart';

class ProfileThreadTabBar extends StatelessWidget {
  const ProfileThreadTabBar({super.key, required this.controller});

  final TabController controller;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        SpotSpacing.lg,
        SpotSpacing.xs,
        SpotSpacing.lg,
        0,
      ),
      child: TabBar(
        controller: controller,
        labelColor: SpotColors.accent,
        unselectedLabelColor: SpotColors.textTertiary,
        indicatorColor: SpotColors.accent,
        indicatorWeight: 1.5,
        dividerColor: Colors.transparent,
        labelStyle: SpotType.caption.copyWith(letterSpacing: 0.8, fontSize: 11),
        tabs: const [
          Tab(text: 'THREADS'),
          Tab(text: 'REPLIES'),
        ],
      ),
    );
  }
}
