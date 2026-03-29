import 'dart:io';
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

import 'package:mobile/services/camera_service.dart';

void main() {
  group('CameraService.applyFaceBlur', () {
    test('blurs detected face regions and leaves other pixels untouched', () async {
      final tempDir = await Directory.systemTemp.createTemp('spot_face_blur_test');
      addTearDown(() async {
        if (tempDir.existsSync()) {
          await tempDir.delete(recursive: true);
        }
      });

      final source = File('${tempDir.path}/source.jpg');
      final image = img.Image(width: 64, height: 64);
      img.fill(image, color: img.ColorRgb8(255, 255, 255));
      for (var y = 20; y < 44; y++) {
        for (var x = 20; x < 44; x++) {
          final checker = (x + y).isEven ? 0 : 255;
          image.setPixelRgb(x, y, checker, 0, 255 - checker);
        }
      }
      await source.writeAsBytes(img.encodeJpg(image, quality: 100), flush: true);

      final service = CameraService.forTesting(
        faceRegionDetector: _FakeFaceRegionDetector(
          const [Rect.fromLTWH(20, 20, 24, 24)],
        ),
        blurDirectoryLoader: () async => tempDir,
      );

      final blurredFile = await service.applyFaceBlur(source);
      final blurredImage = img.decodeImage(await blurredFile.readAsBytes());
      expect(blurredImage, isNotNull);
      expect(blurredFile.path, isNot(source.path));

      final originalCenter = image.getPixel(32, 32);
      final blurredCenter = blurredImage!.getPixel(32, 32);
      expect(blurredCenter.r, isNot(originalCenter.r));
      expect(blurredCenter.b, isNot(originalCenter.b));

      final originalOutside = image.getPixel(5, 5);
      final blurredOutside = blurredImage.getPixel(5, 5);
      expect(blurredOutside.r, originalOutside.r);
      expect(blurredOutside.g, originalOutside.g);
      expect(blurredOutside.b, originalOutside.b);
    });

    test('returns the original file when no faces are detected', () async {
      final tempDir = await Directory.systemTemp.createTemp('spot_face_blur_none');
      addTearDown(() async {
        if (tempDir.existsSync()) {
          await tempDir.delete(recursive: true);
        }
      });

      final source = File('${tempDir.path}/source.jpg');
      final image = img.Image(width: 24, height: 24);
      img.fill(image, color: img.ColorRgb8(20, 30, 40));
      await source.writeAsBytes(img.encodeJpg(image), flush: true);

      final service = CameraService.forTesting(
        faceRegionDetector: _FakeFaceRegionDetector(const []),
        blurDirectoryLoader: () async => tempDir,
      );

      final result = await service.applyFaceBlur(source);
      expect(result.path, source.path);
    });
  });
}

class _FakeFaceRegionDetector implements FaceRegionDetector {
  const _FakeFaceRegionDetector(this.bounds);

  final List<Rect> bounds;

  @override
  Future<List<Rect>> detectFaces(File imageFile) async => bounds;
}
