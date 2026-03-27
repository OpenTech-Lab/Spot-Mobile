import 'package:flutter/material.dart';

import 'package:mobile/theme/spot_theme.dart';

const EdgeInsets spotTabbedScreenHeaderPadding = EdgeInsets.fromLTRB(
  SpotSpacing.lg,
  SpotSpacing.sm,
  SpotSpacing.lg,
  SpotSpacing.sm,
);

const double spotTabbedScreenHeaderRowHeight = 36;

class SpotTabbedScreenHeader extends StatelessWidget {
  const SpotTabbedScreenHeader({
    super.key,
    required this.child,
    this.padding = spotTabbedScreenHeaderPadding,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: padding,
      child: SizedBox(height: spotTabbedScreenHeaderRowHeight, child: child),
    );
  }
}

class SpotTabbedScreenTabBar extends StatelessWidget {
  const SpotTabbedScreenTabBar({
    super.key,
    required this.controller,
    required this.tabs,
  });

  final TabController controller;
  final List<Widget> tabs;

  @override
  Widget build(BuildContext context) {
    return TabBar(
      controller: controller,
      labelColor: SpotColors.accent,
      unselectedLabelColor: SpotColors.textTertiary,
      indicatorColor: SpotColors.accent,
      indicatorWeight: 1.5,
      dividerColor: Colors.transparent,
      labelStyle: SpotType.caption.copyWith(letterSpacing: 0.8, fontSize: 11),
      tabs: tabs,
    );
  }
}
