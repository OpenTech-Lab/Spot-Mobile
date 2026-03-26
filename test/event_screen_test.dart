import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';

import 'package:mobile/features/event/event_screen.dart';
import 'package:mobile/models/event_model.dart';
import 'package:mobile/models/media_post.dart';

void main() {
  test(
    'eventRootThreads excludes replies whose parents exist in the event',
    () {
      final roots = eventRootThreads([
        _post(id: 'root-1', capturedAt: DateTime.utc(2026, 3, 26, 10)),
        _post(
          id: 'reply-1',
          replyToId: 'event-root-1',
          capturedAt: DateTime.utc(2026, 3, 26, 11),
        ),
        _post(id: 'root-2', capturedAt: DateTime.utc(2026, 3, 26, 12)),
      ]);

      expect(roots.map((post) => post.id), ['root-1', 'root-2']);
    },
  );

  test('eventLocationSpots returns every geo-tagged post as a map spot', () {
    final spots = eventLocationSpots([
      _post(id: 'a', latitude: 35.68, longitude: 139.76, spotName: 'Shibuya'),
      _post(id: 'b', latitude: 35.70, longitude: 139.75),
      _post(id: 'c'),
    ]);

    expect(spots.length, 2);
    expect(spots.first.label, 'Shibuya');
    expect(spots.last.label, '#tokyo');
  });

  test('eventLocationCenter averages all visible spots', () {
    final center = eventLocationCenter(const [
      EventLocationSpot(latitude: 35.6, longitude: 139.7, label: 'A'),
      EventLocationSpot(latitude: 35.8, longitude: 139.9, label: 'B'),
    ]);

    expect(center, const LatLng(35.7, 139.8));
  });

  test('eventLocationZoom zooms out as spot spread increases', () {
    final tightZoom = eventLocationZoom(const [
      EventLocationSpot(latitude: 35.6800, longitude: 139.7600, label: 'A'),
      EventLocationSpot(latitude: 35.6805, longitude: 139.7605, label: 'B'),
    ]);
    final wideZoom = eventLocationZoom(const [
      EventLocationSpot(latitude: 35.0, longitude: 139.0, label: 'A'),
      EventLocationSpot(latitude: 37.5, longitude: 141.5, label: 'B'),
    ]);

    expect(tightZoom, greaterThan(wideZoom));
  });

  test(
    'eventLocationSummary includes spot count when multiple markers exist',
    () {
      final summary = eventLocationSummary(
        CivicEvent(
          hashtag: 'tokyo',
          title: '#tokyo',
          posts: [
            _post(id: 'a', latitude: 35.68, longitude: 139.76),
            _post(id: 'b', latitude: 35.69, longitude: 139.77),
          ],
          centerLat: 35.685,
          centerLon: 139.765,
          firstSeen: DateTime.utc(2026, 3, 26),
          participantCount: 2,
        ),
      );

      expect(summary, contains('2 spots'));
      expect(summary, contains('35.6850'));
    },
  );

  test('buildEventTrendSnapshot marks activity as increasing', () {
    final snapshot = buildEventTrendSnapshot(
      CivicEvent(
        hashtag: 'tokyo',
        title: '#tokyo',
        posts: [
          _post(id: 'a', capturedAt: DateTime.utc(2026, 3, 26, 8)),
          _post(id: 'b', capturedAt: DateTime.utc(2026, 3, 26, 9)),
          _post(id: 'c', capturedAt: DateTime.utc(2026, 3, 26, 14)),
          _post(id: 'd', capturedAt: DateTime.utc(2026, 3, 26, 15)),
          _post(id: 'e', capturedAt: DateTime.utc(2026, 3, 26, 16)),
        ],
        firstSeen: DateTime.utc(2026, 3, 26, 8),
        participantCount: 5,
      ),
    );

    expect(snapshot.totalThreadCount, 5);
    expect(snapshot.direction, EventTrendDirection.increasing);
    expect(
      snapshot.recentThreadCount,
      greaterThan(snapshot.earlierThreadCount),
    );
  });

  test('buildEventTrendSnapshot marks activity as decreasing', () {
    final snapshot = buildEventTrendSnapshot(
      CivicEvent(
        hashtag: 'tokyo',
        title: '#tokyo',
        posts: [
          _post(id: 'a', capturedAt: DateTime.utc(2026, 3, 26, 8)),
          _post(id: 'b', capturedAt: DateTime.utc(2026, 3, 26, 9)),
          _post(id: 'c', capturedAt: DateTime.utc(2026, 3, 26, 10)),
          _post(id: 'd', capturedAt: DateTime.utc(2026, 3, 26, 15)),
        ],
        firstSeen: DateTime.utc(2026, 3, 26, 8),
        participantCount: 4,
      ),
    );

    expect(snapshot.direction, EventTrendDirection.decreasing);
    expect(
      snapshot.earlierThreadCount,
      greaterThan(snapshot.recentThreadCount),
    );
  });
}

MediaPost _post({
  required String id,
  DateTime? capturedAt,
  double? latitude,
  double? longitude,
  String? spotName,
  String? replyToId,
}) => MediaPost(
  id: id,
  pubkey: 'pubkey-$id',
  contentHashes: [id],
  capturedAt: capturedAt ?? DateTime.utc(2026, 3, 26),
  latitude: latitude,
  longitude: longitude,
  spotName: spotName,
  replyToId: replyToId,
  eventTags: const ['tokyo'],
  nostrEventId: 'event-$id',
);
