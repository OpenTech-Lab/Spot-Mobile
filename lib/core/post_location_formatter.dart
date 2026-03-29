import 'package:mobile/services/geo_lookup.dart';

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
