import 'dart:io';

import 'package:mobile/core/encryption.dart';
import 'package:mobile/services/camera_service.dart';
import 'package:mobile/services/media_processing_service.dart';

class PostMediaAsset {
  const PostMediaAsset({required this.file, required this.isVideo});

  final File file;
  final bool isVideo;
}

class PreparedPostMedia {
  const PreparedPostMedia({
    required this.files,
    required this.hashes,
    required this.paths,
  });

  final List<File> files;
  final List<String> hashes;
  final List<String> paths;
}

class PostMediaPreparationService {
  PostMediaPreparationService._({
    required Future<File> Function(File imageFile) faceBlurApplier,
    required Future<File> Function(File file, {required bool isVideo})
    uploadOptimizer,
  }) : _faceBlurApplier = faceBlurApplier,
       _uploadOptimizer = uploadOptimizer;

  static final PostMediaPreparationService instance = PostMediaPreparationService._(
    faceBlurApplier: CameraService.instance.applyFaceBlur,
    uploadOptimizer: MediaProcessingService.instance.optimizeForUpload,
  );

  factory PostMediaPreparationService.forTesting({
    required Future<File> Function(File imageFile) faceBlurApplier,
    required Future<File> Function(File file, {required bool isVideo})
    uploadOptimizer,
  }) => PostMediaPreparationService._(
    faceBlurApplier: faceBlurApplier,
    uploadOptimizer: uploadOptimizer,
  );

  final Future<File> Function(File imageFile) _faceBlurApplier;
  final Future<File> Function(File file, {required bool isVideo})
  _uploadOptimizer;

  Future<PreparedPostMedia> prepareAssets(
    Iterable<PostMediaAsset> assets, {
    required bool blurFaces,
  }) async {
    final files = <File>[];
    final hashes = <String>[];
    final paths = <String>[];

    for (final asset in assets) {
      var processedFile = asset.file;
      if (blurFaces && !asset.isVideo) {
        processedFile = await _faceBlurApplier(processedFile);
      }
      processedFile = await _uploadOptimizer(
        processedFile,
        isVideo: asset.isVideo,
      );

      final bytes = await processedFile.readAsBytes();
      files.add(processedFile);
      hashes.add(EncryptionUtils.sha256BytesHex(bytes));
      paths.add(processedFile.path);
    }

    return PreparedPostMedia(files: files, hashes: hashes, paths: paths);
  }
}
