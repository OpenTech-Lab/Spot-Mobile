import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:mobile/widgets/profile_thread_tab_bar.dart';

void main() {
  testWidgets('ProfileThreadTabBar renders thread and reply tabs', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: DefaultTabController(
          length: 2,
          child: Builder(
            builder: (context) => Scaffold(
              body: ProfileThreadTabBar(
                controller: DefaultTabController.of(context),
              ),
            ),
          ),
        ),
      ),
    );

    expect(find.text('THREADS'), findsOneWidget);
    expect(find.text('REPLIES'), findsOneWidget);
  });
}
