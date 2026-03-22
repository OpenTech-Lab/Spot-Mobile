import 'package:geolocator/geolocator.dart';

/// GPS service wrapping [geolocator].
///
/// Usage:
/// ```dart
/// final ok = await LocationService.instance.requestPermission();
/// if (ok) {
///   final pos = await LocationService.instance.getCurrentPosition();
/// }
/// ```
class LocationService {
  LocationService._();

  static final LocationService instance = LocationService._();

  // ── Permission ────────────────────────────────────────────────────────────

  /// Requests the location permission from the user if not already granted.
  /// Returns true if permission is now granted.
  Future<bool> requestPermission() async {
    LocationPermission permission = await Geolocator.checkPermission();

    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }

    if (permission == LocationPermission.deniedForever) {
      // User permanently denied — direct them to app settings.
      return false;
    }

    return permission == LocationPermission.whileInUse ||
        permission == LocationPermission.always;
  }

  /// Returns true if location permission is currently granted.
  Future<bool> isPermissionGranted() async {
    final permission = await Geolocator.checkPermission();
    return permission == LocationPermission.whileInUse ||
        permission == LocationPermission.always;
  }

  // ── Position ──────────────────────────────────────────────────────────────

  /// Returns the device's current GPS position.
  ///
  /// Uses [LocationAccuracy.high] for maximum precision.
  /// Returns null if permission is denied, location services are disabled,
  /// or a timeout occurs.
  Future<Position?> getCurrentPosition() async {
    // Request permission if not yet granted (not just check).
    final granted = await requestPermission();
    if (!granted) return null;

    final serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) return null;

    try {
      // Use medium accuracy with a short timeout for snappy camera UX.
      // Geolocator will still use GPS hardware — medium just allows faster
      // network-assisted fixes in addition to satellite.
      return await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.medium,
        timeLimit: const Duration(seconds: 8),
      );
    } catch (_) {
      // Timeout or platform error — try last known position as fallback.
      try {
        return await Geolocator.getLastKnownPosition();
      } catch (_) {
        return null;
      }
    }
  }

  /// Opens the device's location settings so the user can enable GPS.
  Future<void> openLocationSettings() => Geolocator.openLocationSettings();
}
