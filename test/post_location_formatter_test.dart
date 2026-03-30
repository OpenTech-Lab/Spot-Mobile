import 'package:flutter_test/flutter_test.dart';

import 'package:mobile/core/post_location_formatter.dart';
import 'package:mobile/services/geo_lookup.dart';

void main() {
  test(
    'visiblePublishedLocationText keeps the exact city label for privacy-rounded posts',
    () {
      final label = visiblePublishedLocationText(
        isVirtual: false,
        exactLatitude: 35.6895,
        exactLongitude: 139.6917,
        geoLocation: const GeoLocation(city: 'Tokyo', country: 'Japan'),
      );

      expect(label, 'Japan/Tokyo');
    },
  );

  test(
    'visiblePublishedLocationText keeps exact coordinates for spot check-ins',
    () {
      final label = visiblePublishedLocationText(
        isVirtual: false,
        exactLatitude: 35.6895,
        exactLongitude: 139.6917,
        geoLocation: const GeoLocation(city: 'Tokyo', country: 'Japan'),
        spotName: 'Shibuya Crossing',
      );

      expect(label, 'Shibuya Crossing - Japan/Tokyo (35.7, 139.7)');
    },
  );
}
