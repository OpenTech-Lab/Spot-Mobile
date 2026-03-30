import 'dart:convert';
import 'dart:io';

import 'package:image/image.dart' as img;
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
    this.previewBase64,
    this.previewMimeType,
  });

  final List<File> files;
  final List<String> hashes;
  final List<String> paths;
  final String? previewBase64;
  final String? previewMimeType;
}

class PostMediaPreviewData {
  const PostMediaPreviewData({required this.base64, required this.mimeType});

  final String base64;
  final String mimeType;
}

class PostMediaPreparationService {
  PostMediaPreparationService._({
    required Future<File> Function(File imageFile) faceBlurApplier,
    required Future<File> Function(File file, {required bool isVideo})
    uploadOptimizer,
    required Future<PostMediaPreviewData?> Function(
      File file, {
      required bool isVideo,
    })
    previewBuilder,
  }) : _faceBlurApplier = faceBlurApplier,
       _uploadOptimizer = uploadOptimizer,
       _previewBuilder = previewBuilder;

  static final PostMediaPreparationService instance =
      PostMediaPreparationService._(
        faceBlurApplier: CameraService.instance.applyFaceBlur,
        uploadOptimizer: MediaProcessingService.instance.optimizeForUpload,
        previewBuilder: _buildPreviewData,
      );

  factory PostMediaPreparationService.forTesting({
    required Future<File> Function(File imageFile) faceBlurApplier,
    required Future<File> Function(File file, {required bool isVideo})
    uploadOptimizer,
    Future<PostMediaPreviewData?> Function(File file, {required bool isVideo})?
    previewBuilder,
  }) => PostMediaPreparationService._(
    faceBlurApplier: faceBlurApplier,
    uploadOptimizer: uploadOptimizer,
    previewBuilder: previewBuilder ?? _buildPreviewData,
  );

  final Future<File> Function(File imageFile) _faceBlurApplier;
  final Future<File> Function(File file, {required bool isVideo})
  _uploadOptimizer;
  final Future<PostMediaPreviewData?> Function(
    File file, {
    required bool isVideo,
  })
  _previewBuilder;

  static const _previewMaxDimension = 720;
  static const _previewQuality = 64;

  Future<PreparedPostMedia> prepareAssets(
    Iterable<PostMediaAsset> assets, {
    required bool blurFaces,
  }) async {
    final files = <File>[];
    final hashes = <String>[];
    final paths = <String>[];
    String? previewBase64;
    String? previewMimeType;

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

      if (files.length == 1) {
        final preview = await _previewBuilder(
          processedFile,
          isVideo: asset.isVideo,
        );
        previewBase64 = preview?.base64;
        previewMimeType = preview?.mimeType;
      }
    }

    return PreparedPostMedia(
      files: files,
      hashes: hashes,
      paths: paths,
      previewBase64: previewBase64,
      previewMimeType: previewMimeType,
    );
  }

  static Future<PostMediaPreviewData?> _buildPreviewData(
    File file, {
    required bool isVideo,
  }) async {
    if (isVideo || !file.existsSync()) return null;

    try {
      final bytes = await file.readAsBytes();
      final decoded = img.decodeImage(bytes);
      if (decoded == null) return null;

      final baked = img.bakeOrientation(decoded);
      final resized = _resizePreview(baked);
      final encoded = img.encodeJpg(resized, quality: _previewQuality);
      return PostMediaPreviewData(
        base64: base64Encode(encoded),
        mimeType: 'image/jpeg',
      );
    } catch (_) {
      return null;
    }
  }

  static img.Image _resizePreview(img.Image image) {
    final longest = image.width > image.height ? image.width : image.height;
    if (longest <= _previewMaxDimension) return image;

    if (image.width >= image.height) {
      return img.copyResize(image, width: _previewMaxDimension);
    }
    return img.copyResize(image, height: _previewMaxDimension);
  }
}
