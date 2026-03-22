import 'dart:io';

import 'package:camera/camera.dart';
import 'package:geolocator/geolocator.dart';

import 'package:mobile/services/location_service.dart';

/// GPS snapshot captured at the exact moment of media capture.
class GpsLock {
  final double latitude;
  final double longitude;
  final DateTime timestamp;
  final double accuracy;

  const GpsLock({
    required this.latitude,
    required this.longitude,
    required this.timestamp,
    required this.accuracy,
  });

  @override
  String toString() =>
      'GpsLock(lat: $latitude, lon: $longitude, accuracy: ${accuracy}m, at: $timestamp)';
}

/// Camera service wrapping the Flutter [camera] package.
///
/// Usage:
/// ```dart
/// final cameras = await CameraService.instance.initialize();
/// final controller = CameraController(cameras.first, ResolutionPreset.high);
/// await controller.initialize();
///
/// // Capture photo:
/// final file = await CameraService.instance.capturePhoto(controller);
/// final gps = await CameraService.instance.lockGPS();
/// ```
class CameraService {
  CameraService._();

  static final CameraService instance = CameraService._();

  // ── Initialisation ────────────────────────────────────────────────────────

  /// Returns available cameras.  Must be called before creating a [CameraController].
  Future<List<CameraDescription>> initialize() async {
    return availableCameras();
  }

  // ── Video recording ───────────────────────────────────────────────────────

  /// Starts video recording on [controller].
  Future<void> startRecording(CameraController controller) async {
    if (!controller.value.isInitialized) {
      throw StateError('CameraController is not initialised');
    }
    if (controller.value.isRecordingVideo) return;
    await controller.startVideoRecording();
  }

  /// Stops video recording and returns the captured [XFile].
  Future<XFile> stopRecording(CameraController controller) async {
    if (!controller.value.isRecordingVideo) {
      throw StateError('Not currently recording');
    }
    return controller.stopVideoRecording();
  }

  // ── Photo capture ─────────────────────────────────────────────────────────

  /// Captures a still photo and returns the [XFile].
  Future<XFile> capturePhoto(CameraController controller) async {
    if (!controller.value.isInitialized) {
      throw StateError('CameraController is not initialised');
    }
    return controller.takePicture();
  }

  // ── GPS lock ──────────────────────────────────────────────────────────────

  /// Captures GPS coordinates at the current moment (used at shutter press).
  /// Returns null if GPS is unavailable or permission is denied.
  Future<GpsLock?> lockGPS() async {
    final Position? pos = await LocationService.instance.getCurrentPosition();
    if (pos == null) return null;

    return GpsLock(
      latitude: pos.latitude,
      longitude: pos.longitude,
      timestamp: DateTime.now().toUtc(),
      accuracy: pos.accuracy,
    );
  }

  // ── Face blur ─────────────────────────────────────────────────────────────

  /// Applies face blurring to [imageFile] for Danger Mode.
  ///
  /// Prototype stub: returns the original file unchanged.
  /// TODO: Integrate google_ml_kit FaceDetector + image package to blur
  ///       detected face bounding boxes before publishing.
  Future<File> applyFaceBlur(File imageFile) async {
    // TODO: Implement ML Kit face detection and Gaussian blur
    return imageFile;
  }
}
