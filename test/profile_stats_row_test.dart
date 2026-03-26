import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:mobile/widgets/profile_stats_row.dart';

void main() {
  testWidgets('ProfileStatsRow renders posts, following, and followers', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: ProfileStatsRow(
            postCount: 12,
            followingCount: 34,
            followerCount: 56,
          ),
        ),
      ),
    );

    expect(find.text('12'), findsOneWidget);
    expect(find.text('34'), findsOneWidget);
    expect(find.text('56'), findsOneWidget);
    expect(find.text('Posts'), findsOneWidget);
    expect(find.text('Following'), findsOneWidget);
    expect(find.text('Followers'), findsOneWidget);
  });
}
