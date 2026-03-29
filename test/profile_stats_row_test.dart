import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:mobile/widgets/profile_stats_row.dart';

void main() {
  testWidgets('ProfileStatsRow renders posts, following, and followers', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ProfileStatsRow(
            postCount: 12,
            followingCount: 34,
            followerCount: 56,
            joinedAt: DateTime(2026, 3, 20, 8, 30),
            lastThreadAt: DateTime(2026, 3, 29, 11, 45),
            lastReplyAt: DateTime(2026, 3, 30, 9, 15),
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
    expect(find.text('Joined'), findsOneWidget);
    expect(find.text('Thread'), findsOneWidget);
    expect(find.text('Reply'), findsOneWidget);
    expect(find.text('2026/03/20'), findsOneWidget);
    expect(find.text('2026/03/29'), findsOneWidget);
    expect(find.text('2026/03/30'), findsOneWidget);
  });
}
