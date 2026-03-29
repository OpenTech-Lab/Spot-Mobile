import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:mobile/widgets/tabbed_screen_chrome.dart';

void main() {
  test('tabbedScreenChromeVisibilityForScroll hides on downward scroll', () {
    final visible = tabbedScreenChromeVisibilityForScroll(
      currentVisibility: true,
      direction: ScrollDirection.reverse,
      pixels: 48,
      axisDirection: AxisDirection.down,
    );

    expect(visible, isFalse);
  });

  test('tabbedScreenChromeVisibilityForScroll shows on upward scroll', () {
    final visible = tabbedScreenChromeVisibilityForScroll(
      currentVisibility: false,
      direction: ScrollDirection.forward,
      pixels: 48,
      axisDirection: AxisDirection.down,
    );

    expect(visible, isTrue);
  });

  test('tabbedScreenChromeVisibilityForScroll stays visible at top', () {
    final visible = tabbedScreenChromeVisibilityForScroll(
      currentVisibility: false,
      direction: ScrollDirection.reverse,
      pixels: 0,
      axisDirection: AxisDirection.down,
    );

    expect(visible, isTrue);
  });

  test('tabbedScreenChromeVisibilityForScroll ignores horizontal scroll', () {
    final visible = tabbedScreenChromeVisibilityForScroll(
      currentVisibility: true,
      direction: ScrollDirection.reverse,
      pixels: 48,
      axisDirection: AxisDirection.right,
    );

    expect(visible, isTrue);
  });

  testWidgets('SpotCollapsibleTabbedScreenChrome collapses when hidden', (
    tester,
  ) async {
    await tester.pumpWidget(
      const Directionality(
        textDirection: TextDirection.ltr,
        child: Column(
          children: [
            SpotCollapsibleTabbedScreenChrome(
              visible: true,
              child: SizedBox(height: 60, width: 100),
            ),
          ],
        ),
      ),
    );

    expect(tester.getSize(find.byType(SizedBox)).height, 60);

    await tester.pumpWidget(
      const Directionality(
        textDirection: TextDirection.ltr,
        child: Column(
          children: [
            SpotCollapsibleTabbedScreenChrome(
              visible: false,
              child: SizedBox(height: 60, width: 100),
            ),
          ],
        ),
      ),
    );
    await tester.pump(spotTabbedScreenChromeAnimationDuration);

    final collapsible = tester.widget<AnimatedAlign>(
      find.descendant(
        of: find.byType(SpotCollapsibleTabbedScreenChrome),
        matching: find.byType(AnimatedAlign),
      ),
    );

    expect(collapsible.heightFactor, 0);
  });
}
