import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:mobile/widgets/dismiss_keyboard_on_tap.dart';

void main() {
  testWidgets('tapping empty space dismisses the focused keyboard input', (
    tester,
  ) async {
    await tester.pumpWidget(const MaterialApp(home: _DismissKeyboardHarness()));

    await tester.tap(find.byKey(_DismissKeyboardHarness.fieldKey));
    await tester.pump();

    expect(
      tester
          .widget<TextField>(find.byKey(_DismissKeyboardHarness.fieldKey))
          .focusNode
          ?.hasFocus,
      isTrue,
    );

    await tester.tap(find.byKey(_DismissKeyboardHarness.blankKey));
    await tester.pump();

    expect(
      tester
          .widget<TextField>(find.byKey(_DismissKeyboardHarness.fieldKey))
          .focusNode
          ?.hasFocus,
      isFalse,
    );
  });
}

class _DismissKeyboardHarness extends StatefulWidget {
  const _DismissKeyboardHarness();

  static const fieldKey = ValueKey<String>('dismiss-keyboard-field');
  static const blankKey = ValueKey<String>('dismiss-keyboard-blank');

  @override
  State<_DismissKeyboardHarness> createState() =>
      _DismissKeyboardHarnessState();
}

class _DismissKeyboardHarnessState extends State<_DismissKeyboardHarness> {
  final _focusNode = FocusNode();

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return DismissKeyboardOnTap(
      child: Scaffold(
        body: Column(
          children: [
            TextField(
              key: _DismissKeyboardHarness.fieldKey,
              focusNode: _focusNode,
            ),
            const Expanded(
              child: ColoredBox(
                key: _DismissKeyboardHarness.blankKey,
                color: Colors.transparent,
                child: SizedBox.expand(),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
