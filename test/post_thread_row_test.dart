import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:mobile/models/media_post.dart';
import 'package:mobile/services/geo_lookup.dart';
import 'package:mobile/widgets/post_thread_row.dart';

void main() {
  test('visibleThreadTagsForPost shows only category tag on root posts', () {
    final post = _post(eventTags: const ['tokyo', 'news', 'urgent']);

    expect(visibleThreadTagsForPost(post), ['tokyo']);
  });

  test('visibleThreadTagsForPost shows only sub tags on replies', () {
    final post = _post(
      eventTags: const ['tokyo', 'news', 'urgent'],
      replyToId: 'root-id',
    );

    expect(visibleThreadTagsForPost(post), ['news', 'urgent']);
  });

  test('visibleThreadTagsForPost hides category-only tags on replies', () {
    final post = _post(eventTags: const ['tokyo'], replyToId: 'root-id');

    expect(visibleThreadTagsForPost(post), isEmpty);
  });

  test('threadHeaderLocationForPost shows hidden label without GPS', () {
    final post = _post(eventTags: const ['tokyo']);
    final location = threadHeaderLocationForPost(post);

    expect(location.label, 'Location hidden');
    expect(location.fullLabel, 'Location hidden');
    expect(location.isExpandable, isFalse);
  });

  test('threadHeaderLocationForPost shows virtual label', () {
    final post = _post(eventTags: const ['tokyo'], isVirtual: true);
    final location = threadHeaderLocationForPost(post);

    expect(location.label, 'Virtual');
    expect(location.fullLabel, 'Virtual');
    expect(location.isExpandable, isFalse);
  });

  test('threadHeaderLocationForPost shows country in header for check-ins', () {
    final post = _post(
      eventTags: const ['tokyo'],
      latitude: 35.7,
      longitude: 139.7,
      spotName: 'Shibuya Crossing',
    );
    final location = threadHeaderLocationForPost(
      post,
      geoLocation: const GeoLocation(city: 'Tokyo', country: 'Japan'),
    );

    expect(location.label, 'Japan');
    expect(location.fullLabel, 'Shibuya Crossing  ·  Japan/Tokyo');
    expect(location.isExpandable, isTrue);
  });

  test(
    'threadHeaderLocationForPost shows country label and full place for geo posts',
    () {
      final post = _post(
        eventTags: const ['tokyo'],
        latitude: 35.6895,
        longitude: 139.6917,
      );
      final location = threadHeaderLocationForPost(
        post,
        geoLocation: const GeoLocation(city: 'Tokyo', country: 'Japan'),
      );

      expect(location.label, 'Japan');
      expect(location.fullLabel, 'Japan/Tokyo');
      expect(location.isExpandable, isTrue);
    },
  );

  test(
    'threadHeaderLocationForPost falls back to coarse coordinates without geo lookup',
    () {
      final post = _post(
        eventTags: const ['tokyo'],
        latitude: 35.6895,
        longitude: 139.6917,
      );
      final location = threadHeaderLocationForPost(post);

      expect(location.label, '35.7, 139.7');
      expect(location.fullLabel, '35.7, 139.7');
      expect(location.isExpandable, isFalse);
    },
  );

  testWidgets(
    'ThreadHeaderLocationLabel wraps expandable locations in a tap tooltip',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: const ThreadHeaderLocationLabel(
              location: ThreadHeaderLocation(
                label: 'Japan',
                fullLabel: 'Japan/Tokyo',
              ),
            ),
          ),
        ),
      );

      final tooltip = tester.widget<Tooltip>(find.byType(Tooltip));

      expect(find.text('Japan'), findsOneWidget);
      expect(tooltip.message, 'Japan/Tokyo');
      expect(tooltip.triggerMode, TooltipTriggerMode.tap);
    },
  );

  testWidgets('PostThreadRow shows hidden location only once in the header', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PostThreadRow(
            post: _post(eventTags: const ['tokyo']),
            isLast: true,
          ),
        ),
      ),
    );

    expect(find.text('Location hidden'), findsOneWidget);
  });
}

MediaPost _post({
  required List<String> eventTags,
  String? replyToId,
  double? latitude,
  double? longitude,
  bool isVirtual = false,
  String? spotName,
}) => MediaPost(
  id: 'post-id',
  pubkey: 'pubkey',
  contentHashes: const ['post-id'],
  capturedAt: DateTime.utc(2026, 3, 23),
  eventTags: eventTags,
  replyToId: replyToId,
  latitude: latitude,
  longitude: longitude,
  isVirtual: isVirtual,
  spotName: spotName,
  nostrEventId: 'post-id',
);
