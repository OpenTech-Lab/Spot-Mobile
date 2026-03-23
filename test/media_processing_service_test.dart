import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

import 'package:mobile/services/media_processing_service.dart';

void main() {
  test('optimizeForUpload resizes and recompresses large images', () async {
    final tempDir = await Directory.systemTemp.createTemp(
      'spot-media-processing-',
    );
    addTearDown(() => tempDir.delete(recursive: true));

    final source = File('${tempDir.path}/source.jpg');
    final image = img.Image(width: 2400, height: 1800);
    for (var y = 0; y < image.height; y++) {
      for (var x = 0; x < image.width; x++) {
        image.setPixelRgba(
          x,
          y,
          (x * 13 + y * 17) % 256,
          (x * 7 + y * 11) % 256,
          (x * 19 + y * 5) % 256,
          255,
        );
      }
    }
    await source.writeAsBytes(img.encodeJpg(image, quality: 95));

    final service = MediaProcessingService.forTesting(
      tempDirLoader: () async => tempDir,
    );
    final optimized = await service.optimizeForUpload(source, isVideo: false);
    final optimizedBytes = await optimized.readAsBytes();
    final optimizedImage = img.decodeImage(optimizedBytes);

    expect(optimized.path, isNot(source.path));
    expect(await optimized.length(), lessThan(await source.length()));
    expect(optimizedImage, isNotNull);
    expect(
      [
        optimizedImage!.width,
        optimizedImage.height,
      ].reduce((a, b) => a > b ? a : b),
      lessThanOrEqualTo(MediaProcessingService.uploadImageMaxDimension),
    );
  });

  test('optimizeForUpload keeps videos unchanged', () async {
    final tempDir = await Directory.systemTemp.createTemp(
      'spot-media-processing-video-',
    );
    addTearDown(() => tempDir.delete(recursive: true));

    final source = File('${tempDir.path}/clip.mp4');
    await source.writeAsBytes(List<int>.generate(512, (index) => index % 256));

    final optimized = await MediaProcessingService.instance.optimizeForUpload(
      source,
      isVideo: true,
    );

    expect(optimized.path, source.path);
  });
}
