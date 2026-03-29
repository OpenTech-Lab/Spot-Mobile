import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';

import 'package:mobile/models/media_post.dart';
import 'package:mobile/services/geo_lookup.dart';
import 'package:mobile/widgets/footprint_map_tab.dart';

void main() {
  test('buildFootprintCountryVisitCounts aggregates visits by country', () {
    final counts = buildFootprintCountryVisitCounts(
      [
        _post(id: '1', latitude: 35, longitude: 139),
        _post(id: '2', latitude: 36, longitude: 140),
        _post(id: '3', latitude: 40, longitude: -74),
        _post(id: '4', latitude: 41, longitude: -73, isDangerMode: true),
        _post(id: '5', latitude: 42, longitude: -72, isVirtual: true),
      ],
      resolveCountry: (latitude, longitude) {
        if (longitude > 0) {
          return const GeoLocation(city: 'Tokyo', country: 'Japan');
        }
        return const GeoLocation(city: 'New York', country: 'United States');
      },
    );

    expect(counts['japan'], 2);
    expect(counts['united states of america'], 1);
    expect(counts.length, 2);
  });

  test('footprintCountryVisitLabel uses singular and plural copy', () {
    expect(footprintCountryVisitLabel('Japan', 1), 'Japan · 1 visit');
    expect(footprintCountryVisitLabel('Japan', 2), 'Japan · 2 visits');
  });

  test('footprintCountryFillColor uses visit-count thresholds', () {
    expect(footprintCountryFillColor(0), Colors.transparent);
    expect(footprintCountryFillColor(1), const Color(0xFF424242));
    expect(footprintCountryFillColor(2), const Color(0xFF7A7A7A));
    expect(footprintCountryFillColor(5), const Color(0xFF7A7A7A));
    expect(footprintCountryFillColor(6), const Color(0xFFA8A8A8));
    expect(footprintCountryFillColor(10), const Color(0xFFA8A8A8));
    expect(footprintCountryFillColor(11), Colors.white);
  });

  testWidgets('FootprintMapTab opens the full-screen map route', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            height: 280,
            child: FootprintMapTab(
              posts: const [],
              shapeLoader: () async => const [],
              resolveCountry: (latitude, longitude) => null,
            ),
          ),
        ),
      ),
    );

    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    await tester.tap(
      find.byIcon(CupertinoIcons.arrow_up_left_arrow_down_right),
    );
    await tester.pumpAndSettle();

    expect(find.text(footprintMapTitle), findsOneWidget);
    expect(find.byIcon(CupertinoIcons.back), findsOneWidget);
  });

  testWidgets('full-screen footprint map shows hint and zoom controls', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: FootprintMapScreen(
          posts: [
            _post(id: '1', latitude: 0, longitude: 0),
            _post(id: '2', latitude: 1, longitude: 1),
          ],
          shapeLoader: () async => const [
            FootprintCountryShape(
              name: 'Testland',
              points: [
                LatLng(-70, -170),
                LatLng(-70, 170),
                LatLng(80, 170),
                LatLng(80, -170),
              ],
            ),
          ],
          resolveCountry: (latitude, longitude) =>
              const GeoLocation(city: 'Test City', country: 'Testland'),
        ),
      ),
    );

    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text(footprintMapSelectionHint), findsOneWidget);
    expect(find.byIcon(CupertinoIcons.plus), findsOneWidget);
    expect(find.byIcon(CupertinoIcons.minus), findsOneWidget);
  });
}

MediaPost _post({
  required String id,
  double? latitude,
  double? longitude,
  bool isDangerMode = false,
  bool isVirtual = false,
}) => MediaPost(
  id: id,
  pubkey: 'pubkey-$id',
  contentHashes: [id],
  capturedAt: DateTime.utc(2026, 3, 29),
  latitude: latitude,
  longitude: longitude,
  isDangerMode: isDangerMode,
  isVirtual: isVirtual,
  eventTags: const ['tokyo'],
  nostrEventId: id,
);
