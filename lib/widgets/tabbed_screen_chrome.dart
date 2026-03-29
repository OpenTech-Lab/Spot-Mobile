import 'package:flutter/rendering.dart';
import 'package:flutter/material.dart';

import 'package:mobile/theme/spot_theme.dart';

const EdgeInsets spotTabbedScreenHeaderPadding = EdgeInsets.fromLTRB(
  SpotSpacing.lg,
  SpotSpacing.sm,
  SpotSpacing.lg,
  SpotSpacing.sm,
);

const double spotTabbedScreenHeaderRowHeight = 36;
const Duration spotTabbedScreenChromeAnimationDuration = Duration(
  milliseconds: 180,
);
const double spotTabbedScreenChromeHideThreshold = 12;

bool tabbedScreenChromeVisibilityForScroll({
  required bool currentVisibility,
  required ScrollDirection direction,
  required double pixels,
  required AxisDirection axisDirection,
  double hideThreshold = spotTabbedScreenChromeHideThreshold,
}) {
  final isVertical =
      axisDirection == AxisDirection.down || axisDirection == AxisDirection.up;
  if (!isVertical) return currentVisibility;
  if (pixels <= 0) return true;

  switch (direction) {
    case ScrollDirection.forward:
      return true;
    case ScrollDirection.reverse:
      return pixels > hideThreshold ? false : currentVisibility;
    case ScrollDirection.idle:
      return currentVisibility;
  }
}

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

class SpotCollapsibleTabbedScreenChrome extends StatelessWidget {
  const SpotCollapsibleTabbedScreenChrome({
    super.key,
    required this.visible,
    required this.child,
  });

  final bool visible;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return ClipRect(
      child: AnimatedAlign(
        duration: spotTabbedScreenChromeAnimationDuration,
        curve: Curves.easeOutCubic,
        alignment: Alignment.topCenter,
        heightFactor: visible ? 1 : 0,
        child: AnimatedOpacity(
          duration: spotTabbedScreenChromeAnimationDuration,
          curve: Curves.easeOutCubic,
          opacity: visible ? 1 : 0,
          child: child,
        ),
      ),
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
