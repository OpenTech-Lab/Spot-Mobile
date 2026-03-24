import 'dart:io';

import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

class MediaProcessingService {
  MediaProcessingService._({Future<Directory> Function()? mediaDirLoader})
    : _mediaDirLoader = mediaDirLoader ?? getApplicationSupportDirectory;

  static final MediaProcessingService instance = MediaProcessingService._();

  factory MediaProcessingService.forTesting({
    required Future<Directory> Function() tempDirLoader,
  }) => MediaProcessingService._(mediaDirLoader: tempDirLoader);

  static const uploadImageMaxDimension = 1600;
  static const uploadImageQualityCandidates = [82, 72, 62];

  final Future<Directory> Function() _mediaDirLoader;

  Future<File> optimizeForUpload(File file, {required bool isVideo}) async {
    if (isVideo) return file;
    return _optimizeImage(file);
  }

  bool isVideoPath(String path, {String? mimeType}) {
    if (mimeType?.startsWith('video/') == true) return true;
    final lower = path.toLowerCase();
    return lower.endsWith('.mp4') ||
        lower.endsWith('.mov') ||
        lower.endsWith('.avi') ||
        lower.endsWith('.mkv');
  }

  Future<File> _optimizeImage(File file) async {
    if (!file.existsSync()) return file;

    try {
      final originalBytes = await file.readAsBytes();
      final decoded = img.decodeImage(originalBytes);
      if (decoded == null) return file;

      final baked = img.bakeOrientation(decoded);
      final resized = _resizeToFit(baked, uploadImageMaxDimension);
      List<int>? bestEncoding;

      for (final quality in uploadImageQualityCandidates) {
        final encoded = img.encodeJpg(resized, quality: quality);
        if (bestEncoding == null || encoded.length < bestEncoding.length) {
          bestEncoding = encoded;
        }
      }

      if (bestEncoding == null || bestEncoding.length >= originalBytes.length) {
        return file;
      }

      final baseDir = await _mediaDirLoader();
      final uploadDir = Directory(p.join(baseDir.path, 'spot_upload_media'));
      if (!uploadDir.existsSync()) {
        await uploadDir.create(recursive: true);
      }

      final outputPath = p.join(
        uploadDir.path,
        '${p.basenameWithoutExtension(file.path)}_'
        '${DateTime.now().microsecondsSinceEpoch}.jpg',
      );
      final outputFile = File(outputPath);
      await outputFile.writeAsBytes(bestEncoding, flush: true);
      return outputFile;
    } catch (_) {
      return file;
    }
  }

  img.Image _resizeToFit(img.Image image, int maxDimension) {
    final longest = image.width > image.height ? image.width : image.height;
    if (longest <= maxDimension) return image;

    if (image.width >= image.height) {
      return img.copyResize(image, width: maxDimension);
    }
    return img.copyResize(image, height: maxDimension);
  }
}
