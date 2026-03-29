import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' show Rect;

import 'package:camera/camera.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

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

abstract class FaceRegionDetector {
  Future<List<Rect>> detectFaces(File imageFile);
}

class MlKitFaceRegionDetector implements FaceRegionDetector {
  MlKitFaceRegionDetector()
    : _faceDetector = FaceDetector(
        options: FaceDetectorOptions(
          performanceMode: FaceDetectorMode.accurate,
          enableContours: false,
          enableLandmarks: false,
          enableClassification: false,
          enableTracking: false,
          minFaceSize: 0.08,
        ),
      );

  final FaceDetector _faceDetector;

  @override
  Future<List<Rect>> detectFaces(File imageFile) async {
    final inputImage = InputImage.fromFilePath(imageFile.path);
    final faces = await _faceDetector.processImage(inputImage);
    return faces.map((face) => face.boundingBox).toList(growable: false);
  }
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
  CameraService._({
    FaceRegionDetector? faceRegionDetector,
    Future<Directory> Function()? blurDirectoryLoader,
  }) : _faceRegionDetector = faceRegionDetector ?? MlKitFaceRegionDetector(),
       _blurDirectoryLoader = blurDirectoryLoader ?? getApplicationSupportDirectory;

  static final CameraService instance = CameraService._();

  factory CameraService.forTesting({
    required FaceRegionDetector faceRegionDetector,
    required Future<Directory> Function() blurDirectoryLoader,
  }) => CameraService._(
    faceRegionDetector: faceRegionDetector,
    blurDirectoryLoader: blurDirectoryLoader,
  );

  final FaceRegionDetector _faceRegionDetector;
  final Future<Directory> Function() _blurDirectoryLoader;

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

  /// Applies on-device face blurring to [imageFile] for Danger Mode photos.
  Future<File> applyFaceBlur(File imageFile) async {
    if (!imageFile.existsSync()) return imageFile;

    try {
      final originalBytes = await imageFile.readAsBytes();
      final decoded = img.decodeImage(originalBytes);
      if (decoded == null) return imageFile;

      final baked = img.bakeOrientation(decoded);
      final normalizedInput = await _writeBlurImage(
        baked,
        originalPath: imageFile.path,
        suffix: 'normalized',
        quality: 94,
      );

      try {
        final faceBounds = await _faceRegionDetector.detectFaces(normalizedInput);
        if (faceBounds.isEmpty) {
          return imageFile;
        }

        for (final bounds in faceBounds) {
          _blurFaceRegion(baked, bounds);
        }

        return _writeBlurImage(
          baked,
          originalPath: imageFile.path,
          suffix: 'faces_blurred',
          quality: 90,
        );
      } finally {
        if (normalizedInput.existsSync()) {
          await normalizedInput.delete();
        }
      }
    } catch (_) {
      // Danger Mode blur is best-effort here; if ML Kit fails unexpectedly,
      // keep the publish flow from crashing and return the source image.
      return imageFile;
    }
  }

  void _blurFaceRegion(img.Image image, Rect rawBounds) {
    final expanded = Rect.fromLTRB(
      math.max(0.0, rawBounds.left - rawBounds.width * 0.18),
      math.max(0.0, rawBounds.top - rawBounds.height * 0.22),
      math.min(
        image.width.toDouble(),
        rawBounds.right + rawBounds.width * 0.18,
      ),
      math.min(
        image.height.toDouble(),
        rawBounds.bottom + rawBounds.height * 0.22,
      ),
    );

    final x = expanded.left.floor().clamp(0, image.width - 1).toInt();
    final y = expanded.top.floor().clamp(0, image.height - 1).toInt();
    final width = math.max(
      1,
      expanded.width.ceil(),
    ).clamp(1, image.width - x).toInt();
    final height = math.max(
      1,
      expanded.height.ceil(),
    ).clamp(1, image.height - y).toInt();

    final faceCrop = img.copyCrop(
      image,
      x: x,
      y: y,
      width: width,
      height: height,
    );
    final blurRadius = math.max(12, (math.min(width, height) / 6).round());
    final blurredCrop = img.gaussianBlur(faceCrop, radius: blurRadius);
    img.compositeImage(image, blurredCrop, dstX: x, dstY: y);
  }

  Future<File> _writeBlurImage(
    img.Image image, {
    required String originalPath,
    required String suffix,
    required int quality,
  }) async {
    final baseDir = await _blurDirectoryLoader();
    final blurDir = Directory(p.join(baseDir.path, 'spot_face_blur'));
    if (!blurDir.existsSync()) {
      await blurDir.create(recursive: true);
    }

    final outputPath = p.join(
      blurDir.path,
      '${p.basenameWithoutExtension(originalPath)}_'
      '${suffix}_${DateTime.now().microsecondsSinceEpoch}.jpg',
    );
    final outputFile = File(outputPath);
    await outputFile.writeAsBytes(
      img.encodeJpg(image, quality: quality),
      flush: true,
    );
    return outputFile;
  }
}
