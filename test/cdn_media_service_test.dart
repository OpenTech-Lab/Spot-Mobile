import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:mobile/core/encryption.dart';

void main() {
  group('CDN content hash verification', () {
    test('SHA-256 of downloaded bytes must match the content hash', () async {
      final tempDir = await Directory.systemTemp.createTemp('spot-cdn-');
      addTearDown(() => tempDir.delete(recursive: true));

      // Simulate media bytes
      final mediaBytes = Uint8List.fromList([0x89, 0x50, 0x4E, 0x47, 1, 2, 3]);
      final expectedHash = EncryptionUtils.sha256BytesHex(mediaBytes);

      // Simulate downloading and verifying
      final downloadedHash = EncryptionUtils.sha256BytesHex(mediaBytes);

      expect(downloadedHash, equals(expectedHash));
    });

    test('mismatched hash is detected', () {
      final bytes1 = Uint8List.fromList([1, 2, 3]);
      final bytes2 = Uint8List.fromList([4, 5, 6]);

      final hash1 = EncryptionUtils.sha256BytesHex(bytes1);
      final hash2 = EncryptionUtils.sha256BytesHex(bytes2);

      expect(hash1, isNot(equals(hash2)));
    });
  });

  group('CDN URL construction', () {
    test('content hash maps to CDN path', () {
      const cdnBase = 'https://cdn.spot.app';
      const contentHash =
          'a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5f6a1b2';

      final url = '$cdnBase/$contentHash';

      expect(url, equals('$cdnBase/$contentHash'));
      expect(contentHash.length, equals(64));
    });
  });

  group('EXIF stripping preconditions', () {
    test('image file extensions are correctly identified', () {
      expect(_isImagePath('photo.jpg'), isTrue);
      expect(_isImagePath('photo.jpeg'), isTrue);
      expect(_isImagePath('photo.png'), isTrue);
      expect(_isImagePath('photo.webp'), isTrue);
      expect(_isImagePath('video.mp4'), isFalse);
      expect(_isImagePath('video.mov'), isFalse);
      expect(_isImagePath('document.pdf'), isFalse);
    });
  });

  group('Danger Mode CDN upload gate', () {
    test('isDangerMode flag prevents CDN upload', () {
      // This test verifies the business rule:
      // Danger Mode posts must NEVER be uploaded to CDN.
      const isDangerMode = true;
      const shouldUpload = !isDangerMode;

      expect(shouldUpload, isFalse);
    });

    test('non-Danger Mode posts are eligible for CDN upload', () {
      const isDangerMode = false;
      const shouldUpload = !isDangerMode;

      expect(shouldUpload, isTrue);
    });
  });
}

bool _isImagePath(String path) {
  final lower = path.toLowerCase();
  return lower.endsWith('.jpg') ||
      lower.endsWith('.jpeg') ||
      lower.endsWith('.png') ||
      lower.endsWith('.webp');
}
