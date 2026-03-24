import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:path_provider/path_provider.dart';

import 'package:mobile/core/encryption.dart';
import 'package:mobile/services/cache_manager.dart';
import 'package:mobile/services/user_prefs_service.dart';

/// CDN media service for accelerated media fetch and upload.
///
/// Fetch path: GET https://<cloudfront>/‹sha256Hash›
/// Upload path: POST presign-lambda → presigned S3 PUT URL → PUT file bytes
///
/// All objects are keyed by their SHA-256 content hash, making the store
/// content-addressed and naturally deduplicating.
class CdnMediaService {
  CdnMediaService._({
    HttpClient? httpClient,
    String? cdnBaseUrl,
    String? presignEndpoint,
  })  : _httpClient = httpClient ?? HttpClient(),
        _cdnBaseUrl = cdnBaseUrl ?? _defaultCdnBaseUrl,
        _presignEndpoint = presignEndpoint ?? _defaultPresignEndpoint;

  static final CdnMediaService instance = CdnMediaService._();

  /// Creates an instance with injected dependencies for testing.
  factory CdnMediaService.forTesting({
    HttpClient? httpClient,
    String? cdnBaseUrl,
    String? presignEndpoint,
  }) =>
      CdnMediaService._(
        httpClient: httpClient,
        cdnBaseUrl: cdnBaseUrl,
        presignEndpoint: presignEndpoint,
      );

  final HttpClient _httpClient;
  final String _cdnBaseUrl;
  final String _presignEndpoint;

  /// Injected at build time via `--dart-define`:
  ///
  ///   flutter build apk \
  ///     --dart-define=CDN_BASE_URL=https://d1234.cloudfront.net \
  ///     --dart-define=CDN_PRESIGN_URL=https://xyz.lambda-url.ap-northeast-1.on.aws
  ///
  /// In GitHub Actions, feed from secrets:
  ///
  ///   --dart-define=CDN_BASE_URL=${{ secrets.CDN_BASE_URL }}
  ///   --dart-define=CDN_PRESIGN_URL=${{ secrets.CDN_PRESIGN_URL }}
  ///
  /// Falls back to empty string (CDN disabled) when not provided.
  static const _defaultCdnBaseUrl = String.fromEnvironment('CDN_BASE_URL');
  static const _defaultPresignEndpoint = String.fromEnvironment('CDN_PRESIGN_URL');

  static const _fetchTimeout = Duration(seconds: 10);
  static const _presignTimeout = Duration(seconds: 15);
  static const _uploadTimeout = Duration(seconds: 30);

  /// Max response body size for CDN fetches (100 MB).
  /// Prevents OOM on mobile when downloading large videos.
  static const _maxFetchBytes = 100 * 1024 * 1024;

  /// Whether the CDN endpoint is configured (build-time).
  bool get isConfigured => _cdnBaseUrl.isNotEmpty;

  /// Whether CDN fetch is enabled (configured + user preference).
  bool get isEnabled => isConfigured && UserPrefsService.instance.cdnEnabled;

  /// Whether CDN upload is enabled (configured + user preference).
  bool get isUploadEnabled =>
      _presignEndpoint.isNotEmpty && UserPrefsService.instance.cdnUploadEnabled;

  // ── Fetch ──────────────────────────────────────────────────────────────────

  /// Fetches media from CDN by content hash.
  ///
  /// Returns the local [File] on success (also cached via [CacheManager]),
  /// or null if the CDN does not have this content or the fetch fails.
  Future<File?> fetchFromCdn(String contentHash) async {
    if (!isEnabled) return null;

    try {
      final uri = Uri.parse('$_cdnBaseUrl/$contentHash');
      final request = await _httpClient
          .getUrl(uri)
          .timeout(_fetchTimeout);
      final response = await request.close().timeout(_fetchTimeout);

      if (response.statusCode != 200) {
        await response.drain<void>();
        return null;
      }

      final bytes = await _collectBytes(response);
      if (bytes == null) return null; // exceeded size cap

      // Verify SHA-256 integrity
      final downloadedHash = EncryptionUtils.sha256BytesHex(
        Uint8List.fromList(bytes),
      );
      if (downloadedHash != contentHash) {
        return null;
      }

      // Determine extension from Content-Type
      final contentType = response.headers.contentType;
      final ext = _extensionFromContentType(contentType);

      // Save to temp directory and register in cache
      final tempDir = await getTemporaryDirectory();
      final file = File(
        '${tempDir.path}/spot_cdn_media/$contentHash$ext',
      );
      await file.parent.create(recursive: true);
      await file.writeAsBytes(bytes);

      await CacheManager.instance.addToCache(contentHash, file.path);
      return file;
    } on TimeoutException {
      return null;
    } catch (_) {
      return null;
    }
  }

  // ── Upload ─────────────────────────────────────────────────────────────────

  /// Uploads media to CDN via presigned S3 PUT URL.
  ///
  /// Steps:
  /// 1. Request presigned URL from Lambda (with Nostr wallet signature)
  /// 2. PUT file bytes directly to S3
  ///
  /// The file at [filePath] is the already-optimized output of
  /// [MediaProcessingService], which strips EXIF during re-encode. We upload
  /// the exact bytes whose SHA-256 matches [contentHash] — no further
  /// transformation, so the CDN content is hash-verifiable.
  ///
  /// This is fire-and-forget — failures are silently ignored since P2P
  /// seeding already ensures availability.
  ///
  /// [signPayload] is a callback that signs the message string using the
  /// user's Nostr wallet and returns (pubkey, signature).
  Future<void> uploadToCdn({
    required String contentHash,
    required String filePath,
    required Future<PresignAuth> Function(String message) signPayload,
    String? contentType,
  }) async {
    if (!isUploadEnabled) return;

    try {
      final file = File(filePath);
      if (!file.existsSync()) return;

      // Upload the exact optimized bytes — no re-encoding so hash stays valid.
      final bytes = await file.readAsBytes();
      final isImage = _isImagePath(filePath);

      final resolvedContentType =
          contentType ?? (isImage ? 'image/jpeg' : 'application/octet-stream');

      // Request presigned URL
      final timestamp =
          (DateTime.now().toUtc().millisecondsSinceEpoch ~/ 1000).toString();
      final message = 'PUT:$contentHash:$timestamp';
      final auth = await signPayload(message);

      final presignUri = Uri.parse(_presignEndpoint);
      final presignRequest = await _httpClient
          .postUrl(presignUri)
          .timeout(_presignTimeout);
      presignRequest.headers.contentType = ContentType.json;
      presignRequest.write(jsonEncode({
        'pubkey': auth.pubkey,
        'contentHash': contentHash,
        'timestamp': timestamp,
        'signature': auth.signature,
        'contentType': resolvedContentType,
      }));
      final presignResponse =
          await presignRequest.close().timeout(_presignTimeout);

      if (presignResponse.statusCode != 200) {
        await presignResponse.drain<void>();
        return;
      }

      final presignBody = await _collectString(presignResponse);
      final presignJson = jsonDecode(presignBody) as Map<String, dynamic>;
      final uploadUrl = presignJson['uploadUrl'] as String?;
      if (uploadUrl == null) return;

      // PUT to S3 via presigned URL
      final putUri = Uri.parse(uploadUrl);
      final putRequest = await _httpClient
          .putUrl(putUri)
          .timeout(_uploadTimeout);
      putRequest.headers.contentType =
          ContentType.parse(resolvedContentType);
      putRequest.contentLength = bytes.length;
      putRequest.add(bytes);
      final putResponse = await putRequest.close().timeout(_uploadTimeout);
      await putResponse.drain<void>();
      // Silently ignore non-200 — P2P is the fallback.
    } on TimeoutException {
      // CDN upload timeout — acceptable, P2P covers it.
    } catch (_) {
      // CDN upload failed — acceptable, P2P covers it.
    }
  }

  // ── Helpers ────────────────────────────────────────────────────────────────

  static bool _isImagePath(String path) {
    final lower = path.toLowerCase();
    return lower.endsWith('.jpg') ||
        lower.endsWith('.jpeg') ||
        lower.endsWith('.png') ||
        lower.endsWith('.webp');
  }

  static String _extensionFromContentType(ContentType? contentType) {
    if (contentType == null) return '';
    final sub = contentType.subType.toLowerCase();
    return switch (sub) {
      'jpeg' => '.jpg',
      'png' => '.png',
      'webp' => '.webp',
      'mp4' => '.mp4',
      'quicktime' => '.mov',
      _ => '',
    };
  }

  /// Collects response bytes with a size cap to prevent OOM on mobile.
  /// Returns null if the response exceeds [_maxFetchBytes].
  static Future<Uint8List?> _collectBytes(HttpClientResponse response) async {
    final builder = BytesBuilder(copy: false);
    await for (final chunk in response) {
      builder.add(chunk);
      if (builder.length > _maxFetchBytes) return null;
    }
    return builder.takeBytes();
  }

  static Future<String> _collectString(HttpClientResponse response) async {
    final builder = StringBuffer();
    await for (final chunk in response.transform(utf8.decoder)) {
      builder.write(chunk);
    }
    return builder.toString();
  }
}

/// Authentication payload returned by the wallet signing callback.
class PresignAuth {
  const PresignAuth({required this.pubkey, required this.signature});

  final String pubkey;
  final String signature;
}
