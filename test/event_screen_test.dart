import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';

import 'package:mobile/features/event/event_screen.dart';
import 'package:mobile/models/event_model.dart';
import 'package:mobile/models/media_post.dart';
import 'package:mobile/models/witness_model.dart';
import 'package:mobile/theme/spot_theme.dart';

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

  test('eventDiscoverSearchQuery prefixes the event hashtag for Discover', () {
    final query = eventDiscoverSearchQuery(
      CivicEvent(
        hashtag: 'tokyo',
        title: '#tokyo',
        posts: [_post(id: 'root-1')],
        firstSeen: DateTime.utc(2026, 3, 26, 10),
        participantCount: 1,
      ),
    );

    expect(query, '#tokyo');
  });

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

  test('eventLocationZoom can zoom out to world scale for global events', () {
    final worldZoom = eventLocationZoom(const [
      EventLocationSpot(latitude: 37.7749, longitude: -122.4194, label: 'A'),
      EventLocationSpot(latitude: 51.5072, longitude: -0.1276, label: 'B'),
      EventLocationSpot(latitude: -33.8688, longitude: 151.2093, label: 'C'),
    ]);

    expect(worldZoom, eventLocationMinZoom);
  });

  test(
    'stepEventLocationZoom clamps manual zooming within supported bounds',
    () {
      expect(
        stepEventLocationZoom(eventLocationMaxZoom, eventLocationZoomStep),
        eventLocationMaxZoom,
      );
      expect(
        stepEventLocationZoom(eventLocationMinZoom, -eventLocationZoomStep),
        eventLocationMinZoom,
      );
    },
  );

  test(
    'witnessCooldownRemainingForUsers returns remaining time for a recent witness',
    () {
      final remaining = witnessCooldownRemainingForUsers(
        [
          _witness(
            id: 'w1',
            userId: 'pubkey-self',
            type: WitnessType.confirm,
            timestamp: DateTime.utc(2026, 3, 26, 12, 0, 0),
          ),
        ],
        const ['pubkey-self'],
        now: DateTime.utc(2026, 3, 26, 12, 0, 30),
      );

      expect(remaining, isNotNull);
      expect(remaining!.inSeconds, 30);
    },
  );

  test('witnessCooldownRemainingForUsers expires after one minute', () {
    final remaining = witnessCooldownRemainingForUsers(
      [
        _witness(
          id: 'w1',
          userId: 'pubkey-self',
          type: WitnessType.confirm,
          timestamp: DateTime.utc(2026, 3, 26, 12, 0, 0),
        ),
      ],
      const ['pubkey-self'],
      now: DateTime.utc(2026, 3, 26, 12, 1, 1),
    );

    expect(remaining, isNull);
  });

  test('formatWitnessCooldown renders minute-second countdown text', () {
    expect(formatWitnessCooldown(const Duration(seconds: 59)), '0:59');
    expect(formatWitnessCooldown(const Duration(seconds: 60)), '1:00');
  });

  test('eventLocationMarkerColor highlights the first spot distinctly', () {
    expect(eventLocationMarkerColor(0), SpotColors.warning);
    expect(eventLocationMarkerColor(1), SpotColors.accent);
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

  test(
    'selectedWitnessTypeForUsers picks the latest witness for the actor',
    () {
      final selected = selectedWitnessTypeForUsers(
        [
          _witness(
            id: 'w1',
            userId: 'pubkey-self',
            type: WitnessType.seen,
            timestamp: DateTime.utc(2026, 3, 26, 9),
          ),
          _witness(
            id: 'w2',
            userId: 'supabase-self',
            type: WitnessType.confirm,
            timestamp: DateTime.utc(2026, 3, 26, 10),
          ),
          _witness(
            id: 'w3',
            userId: 'other',
            type: WitnessType.deny,
            timestamp: DateTime.utc(2026, 3, 26, 11),
          ),
        ],
        const ['pubkey-self', 'supabase-self'],
      );

      expect(selected, WitnessType.confirm);
    },
  );

  test(
    'eventWithToggledWitness removes the current user signal on repeat tap',
    () {
      final updated = eventWithToggledWitness(
        event: _eventWithWitnesses([
          _witness(
            id: 'mine',
            userId: 'pubkey-self',
            type: WitnessType.confirm,
            timestamp: DateTime.utc(2026, 3, 26, 10),
          ),
        ]),
        userIds: const ['pubkey-self'],
        canonicalUserId: 'pubkey-self',
        tappedType: WitnessType.confirm,
        timestamp: DateTime.utc(2026, 3, 26, 12),
      );

      expect(updated.witnesses, isEmpty);
      expect(
        selectedWitnessTypeForUsers(updated.witnesses, const ['pubkey-self']),
        isNull,
      );
    },
  );

  test(
    'eventWithToggledWitness replaces the current user signal with the new one',
    () {
      final updated = eventWithToggledWitness(
        event: _eventWithWitnesses([
          _witness(
            id: 'mine',
            userId: 'pubkey-self',
            type: WitnessType.seen,
            timestamp: DateTime.utc(2026, 3, 26, 10),
          ),
          _witness(
            id: 'other',
            userId: 'other-user',
            type: WitnessType.confirm,
            timestamp: DateTime.utc(2026, 3, 26, 11),
          ),
        ]),
        userIds: const ['pubkey-self'],
        canonicalUserId: 'pubkey-self',
        tappedType: WitnessType.deny,
        timestamp: DateTime.utc(2026, 3, 26, 12),
      );

      expect(updated.confirmCount, 1);
      expect(updated.seenCount, 0);
      expect(updated.denyCount, 1);
      expect(
        selectedWitnessTypeForUsers(updated.witnesses, const ['pubkey-self']),
        WitnessType.deny,
      );
    },
  );
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

Witness _witness({
  required String id,
  required String userId,
  required WitnessType type,
  required DateTime timestamp,
}) => Witness(
  id: id,
  eventId: 'tokyo',
  userId: userId,
  type: type,
  timestamp: timestamp,
  weight: 0.5,
);

CivicEvent _eventWithWitnesses(List<Witness> witnesses) => CivicEvent(
  hashtag: 'tokyo',
  title: '#tokyo',
  posts: [
    _post(id: 'root-a', capturedAt: DateTime.utc(2026, 3, 26, 8)),
    _post(id: 'root-b', capturedAt: DateTime.utc(2026, 3, 26, 9)),
  ],
  firstSeen: DateTime.utc(2026, 3, 26, 8),
  participantCount: 2,
  witnesses: witnesses,
);
