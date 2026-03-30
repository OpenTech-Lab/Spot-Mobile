import 'package:mobile/services/geo_lookup.dart';

/// Rounds a coordinate to the nearest 0.5° (≈55 km) for city-level privacy.
double? privacyRoundedPostCoordinate(double? value) =>
    value == null ? null : (value * 2).roundToDouble() / 2.0;

double? publishedPostLatitude({
  required double? exactLatitude,
  String? spotName,
}) {
  if (_usesExactPublishedCoordinates(spotName)) return exactLatitude;
  return privacyRoundedPostCoordinate(exactLatitude);
}

double? publishedPostLongitude({
  required double? exactLongitude,
  String? spotName,
}) {
  if (_usesExactPublishedCoordinates(spotName)) return exactLongitude;
  return privacyRoundedPostCoordinate(exactLongitude);
}

/// Builds the visible location label that should survive publish for a post.
///
/// Normal posts keep the city/country resolved from the original GPS lock, but
/// use privacy-rounded coordinates as the fallback when reverse-geocoding is
/// unavailable. Spot check-ins keep exact coordinates.
String visiblePublishedLocationText({
  required bool isVirtual,
  required double? exactLatitude,
  required double? exactLongitude,
  GeoLocation? geoLocation,
  String? spotName,
}) {
  final resolvedGeoLocation =
      geoLocation ??
      (exactLatitude == null || exactLongitude == null
          ? null
          : GeoLookup.instance.nearest(exactLatitude, exactLongitude));

  return visiblePostLocationText(
    isVirtual: isVirtual,
    latitude: publishedPostLatitude(
      exactLatitude: exactLatitude,
      spotName: spotName,
    ),
    longitude: publishedPostLongitude(
      exactLongitude: exactLongitude,
      spotName: spotName,
    ),
    geoLocation: resolvedGeoLocation,
    spotName: spotName,
  );
}

String visiblePostLocationText({
  required bool isVirtual,
  required double? latitude,
  required double? longitude,
  GeoLocation? geoLocation,
  String? spotName,
}) {
  if (isVirtual) {
    return 'Virtual';
  }

  if (latitude == null || longitude == null) {
    return 'Location hidden';
  }

  final coordinates = _coordinateLocationLabel(latitude, longitude);
  final place = geoLocation != null
      ? '${geoLocation.country}/${geoLocation.city}'
      : null;
  final trimmedSpotName = spotName?.trim();
  final hasSpotName = trimmedSpotName != null && trimmedSpotName.isNotEmpty;

  if (hasSpotName) {
    if (place != null) return '$trimmedSpotName - $place ($coordinates)';
    return '$trimmedSpotName - $coordinates';
  }

  if (place != null) return place;
  return coordinates;
}

String _coordinateLocationLabel(double latitude, double longitude) {
  return '${latitude.toStringAsFixed(1)}, ${longitude.toStringAsFixed(1)}';
}

bool _usesExactPublishedCoordinates(String? spotName) {
  final trimmedSpotName = spotName?.trim();
  return trimmedSpotName != null && trimmedSpotName.isNotEmpty;
}
