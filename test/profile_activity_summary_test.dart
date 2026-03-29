import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:mobile/models/media_post.dart';
import 'package:mobile/widgets/profile_activity_summary.dart';

void main() {
  test(
    'buildProfileActivitySummary reports created time, last thread/reply, and top locations',
    () {
      final summary = buildProfileActivitySummary(
        accountCreatedAt: DateTime.utc(2026, 3, 20, 8),
        posts: [
          _post(
            id: 'thread-1',
            capturedAt: DateTime.utc(2026, 3, 28, 9),
            latitude: 35.68,
            longitude: 139.76,
          ),
          _post(
            id: 'thread-2',
            capturedAt: DateTime.utc(2026, 3, 29, 11),
            latitude: 35.69,
            longitude: 139.75,
          ),
          _post(
            id: 'reply-1',
            replyToId: 'thread-1',
            capturedAt: DateTime.utc(2026, 3, 29, 15),
            latitude: 35.72,
            longitude: 139.79,
          ),
          _post(
            id: 'reply-2',
            replyToId: 'thread-2',
            capturedAt: DateTime.utc(2026, 3, 27, 8),
            latitude: 34.68,
            longitude: 135.49,
          ),
          _post(
            id: 'reply-3',
            replyToId: 'thread-2',
            capturedAt: DateTime.utc(2026, 3, 29, 16),
            latitude: 34.66,
            longitude: 135.46,
          ),
          _post(
            id: 'reply-4',
            replyToId: 'thread-2',
            capturedAt: DateTime.utc(2026, 3, 29, 17),
            latitude: 51.50,
            longitude: -0.12,
          ),
          _post(
            id: 'hidden',
            replyToId: 'thread-2',
            capturedAt: DateTime.utc(2026, 3, 29, 18),
          ),
          _post(
            id: 'virtual',
            capturedAt: DateTime.utc(2026, 3, 29, 19),
            latitude: 40.71,
            longitude: -74.00,
            isVirtual: true,
          ),
        ],
      );

      expect(summary.accountCreatedAt, DateTime.utc(2026, 3, 20, 8));
      expect(summary.lastThreadAt, DateTime.utc(2026, 3, 29, 19));
      expect(summary.lastReplyAt, DateTime.utc(2026, 3, 29, 18));
      expect(
        summary.topLocations.map(
          (location) => (location.label, location.count),
        ),
        [('35.7, 139.8', 3), ('34.7, 135.5', 2), ('51.5, -0.1', 1)],
      );
    },
  );

  testWidgets(
    'ProfileActivitySummaryChips renders compact chips without a section card heading',
    (tester) async {
      const summary = ProfileActivitySummary(
        accountCreatedAt: null,
        lastThreadAt: null,
        lastReplyAt: null,
        topLocations: [
          ProfileLocationStat(label: 'Japan/Tokyo', count: 3),
          ProfileLocationStat(label: 'Japan/Osaka', count: 2),
        ],
      );

      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(body: ProfileActivitySummaryChips(summary: summary)),
        ),
      );

      expect(find.byType(Wrap), findsOneWidget);
      expect(find.textContaining('Created'), findsOneWidget);
      expect(find.textContaining('Last thread'), findsOneWidget);
      expect(find.textContaining('Last reply'), findsOneWidget);
      expect(find.textContaining('Top 1'), findsOneWidget);
      expect(find.textContaining('Top 2'), findsOneWidget);
      expect(find.text('Top locations'), findsNothing);
    },
  );
}

MediaPost _post({
  required String id,
  required DateTime capturedAt,
  String? replyToId,
  double? latitude,
  double? longitude,
  bool isVirtual = false,
}) => MediaPost(
  id: id,
  pubkey: 'pubkey-1',
  contentHashes: [id],
  capturedAt: capturedAt,
  latitude: latitude,
  longitude: longitude,
  isVirtual: isVirtual,
  replyToId: replyToId,
  eventTags: const ['tokyo'],
  nostrEventId: id,
);
