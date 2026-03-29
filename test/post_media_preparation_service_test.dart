import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:mobile/services/post_media_preparation_service.dart';

void main() {
  group('PostMediaPreparationService.prepareAssets', () {
    test('blurs only photo assets when blurFaces is enabled', () async {
      final tempDir = await Directory.systemTemp.createTemp('spot_post_media_prep');
      addTearDown(() async {
        if (tempDir.existsSync()) {
          await tempDir.delete(recursive: true);
        }
      });

      final photo = await File('${tempDir.path}/photo.jpg').writeAsBytes(
        const [1, 2, 3],
        flush: true,
      );
      final video = await File('${tempDir.path}/video.mp4').writeAsBytes(
        const [4, 5, 6],
        flush: true,
      );

      var blurCalls = 0;
      final optimizedIsVideo = <bool>[];

      final service = PostMediaPreparationService.forTesting(
        faceBlurApplier: (file) async {
          blurCalls++;
          final blurred = File('${tempDir.path}/blurred_${file.uri.pathSegments.last}');
          await blurred.writeAsBytes(const [9, 9, 9], flush: true);
          return blurred;
        },
        uploadOptimizer: (file, {required isVideo}) async {
          optimizedIsVideo.add(isVideo);
          return file;
        },
      );

      final prepared = await service.prepareAssets(
        [
          PostMediaAsset(file: photo, isVideo: false),
          PostMediaAsset(file: video, isVideo: true),
        ],
        blurFaces: true,
      );

      expect(blurCalls, 1);
      expect(optimizedIsVideo, [false, true]);
      expect(prepared.files, hasLength(2));
      expect(prepared.hashes, hasLength(2));
      expect(prepared.paths.first, contains('blurred_photo.jpg'));
      expect(prepared.paths.last, video.path);
    });

    test('skips face blur entirely when blurFaces is disabled', () async {
      final tempDir = await Directory.systemTemp.createTemp('spot_post_media_no_blur');
      addTearDown(() async {
        if (tempDir.existsSync()) {
          await tempDir.delete(recursive: true);
        }
      });

      final photo = await File('${tempDir.path}/photo.jpg').writeAsBytes(
        const [1, 2, 3],
        flush: true,
      );

      var blurCalls = 0;

      final service = PostMediaPreparationService.forTesting(
        faceBlurApplier: (file) async {
          blurCalls++;
          return file;
        },
        uploadOptimizer: (file, {required isVideo}) async => file,
      );

      await service.prepareAssets(
        [PostMediaAsset(file: photo, isVideo: false)],
        blurFaces: false,
      );

      expect(blurCalls, 0);
    });
  });
}
