import 'package:flutter/material.dart';

/// Dismisses the active keyboard focus when the user taps empty screen space.
///
/// Wrapped around the app shell so every route, sheet, and dialog inherits the
/// same unfocus behavior without adding per-screen gesture handlers.
class DismissKeyboardOnTap extends StatelessWidget {
  const DismissKeyboardOnTap({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onTap: () => FocusManager.instance.primaryFocus?.unfocus(),
      child: child,
    );
  }
}
