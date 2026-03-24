import 'dart:io';

import 'package:mobile/features/p2p/p2p_service.dart';
import 'package:mobile/services/cache_manager.dart';
import 'package:mobile/services/cdn_media_service.dart';

/// Tiered media resolver: Local cache → CDN → P2P.
///
/// Conforms to the [MediaFetcher] typedef in [MediaSyncService] so it can be
/// used as a drop-in replacement for [P2PService.instance.requestMedia].
///
/// Tier 0 — Local cache ([CacheManager]): instant, free.
/// Tier 1 — CDN ([CdnMediaService]): ~50–200 ms globally, low cost.
/// Tier 2 — P2P ([P2PService]): variable latency, free, requires peer online.
class MediaResolver {
  MediaResolver._({
    CacheManager? cacheManager,
    CdnMediaService? cdnMediaService,
    P2PService? p2pService,
  })  : _cache = cacheManager ?? CacheManager.instance,
        _cdn = cdnMediaService ?? CdnMediaService.instance,
        _p2p = p2pService ?? P2PService.instance;

  static final MediaResolver instance = MediaResolver._();

  /// Creates an instance with injected dependencies for testing.
  factory MediaResolver.forTesting({
    CacheManager? cacheManager,
    CdnMediaService? cdnMediaService,
    P2PService? p2pService,
  }) =>
      MediaResolver._(
        cacheManager: cacheManager,
        cdnMediaService: cdnMediaService,
        p2pService: p2pService,
      );

  final CacheManager _cache;
  final CdnMediaService _cdn;
  final P2PService _p2p;

  /// Resolves a media file by content hash using the tiered strategy.
  ///
  /// This method matches the [MediaFetcher] signature:
  /// `Future<File?> Function(String contentHash, {String? authorPubkey})`
  Future<File?> resolve(String contentHash, {String? authorPubkey}) async {
    // Tier 0: Local cache
    final cached = _cache.getCached(contentHash);
    if (cached != null) return cached;

    // Tier 1: CDN
    if (_cdn.isEnabled) {
      final cdnFile = await _cdn.fetchFromCdn(contentHash);
      if (cdnFile != null) return cdnFile;
    }

    // Tier 2: P2P fallback
    return _p2p.requestMedia(contentHash, authorPubkey: authorPubkey);
  }
}
