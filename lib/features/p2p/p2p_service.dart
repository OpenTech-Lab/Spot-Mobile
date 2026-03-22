import 'dart:io';

import 'package:mobile/services/cache_manager.dart';

/// P2P media swarm service.
///
/// Spec v1.4 §6: 100% on-device storage; raw files replicated via libp2p
/// bitswap on-demand. Automatic swarm caching: viewers who watch ≥50% of
/// content become seeders (WiFi-only by default). Hard cache cap: 5 GB.
///
/// This is a **stub implementation**.  The production version must replace
/// these methods with calls to a dart_libp2p binding or a native-channel
/// bridge to a Go/Rust libp2p node running in the background.
///
/// TODO: Replace stub with dart_libp2p (or a Flutter platform channel
///       bridge to go-libp2p) when the Dart bindings mature.
///         - Kademlia DHT (peer discovery by content hash)
///         - libp2p holepunch (NAT traversal)
///         - Bitswap (block-level data exchange, IPFS-compatible)
///         - GossipSub (real-time peer announcements + revocation broadcast)
class P2PService {
  P2PService._();

  static final P2PService instance = P2PService._();

  bool _started = false;
  int _seedingCount = 0;

  // ── Swarm lifecycle ───────────────────────────────────────────────────────

  Future<void> startSwarm() async {
    // TODO: initialise dart_libp2p host
    // TODO: bootstrap Kademlia DHT
    // TODO: join GossipSub topic 'spot/v1'
    _started = true;
  }

  Future<void> stopSwarm() async {
    // TODO: cleanly shut down libp2p host
    _started = false;
    _seedingCount = 0;
  }

  // ── Seeding ───────────────────────────────────────────────────────────────

  /// Announces [filePath] to the DHT keyed by [contentHash].
  ///
  /// Registers the file in [CacheManager] (enforces the 5 GB cap) and
  /// increments the seeding counter.
  ///
  /// Production: pin the file into the local Bitswap blockstore and
  /// provide the CID on the DHT so peers can discover and fetch it.
  Future<void> seedMedia(String filePath, String contentHash) async {
    // TODO: add file blocks to Bitswap blockstore
    // TODO: provide CID on DHT (dht.provide(cid))
    await CacheManager.instance.addToCache(contentHash, filePath);
    _seedingCount++;
  }

  /// Seeds [contentHash] only if [watchFraction] ≥ 0.5 and the device is on
  /// WiFi (spec v1.4 §6: "WiFi-only by default").
  ///
  /// Called by the media viewer when the user has watched ≥50% of a video
  /// or fully loaded a photo.
  Future<void> seedIfEligible(String contentHash, String filePath,
      double watchFraction) async {
    if (watchFraction < 0.5) return;
    if (!await _isOnWifi()) return;
    await seedMedia(filePath, contentHash);
  }

  // ── Fetching ──────────────────────────────────────────────────────────────

  /// Requests media with [contentHash] from the swarm.
  ///
  /// Returns a locally cached [File] if available, otherwise queries the
  /// swarm (stub: always returns null).
  Future<File?> requestMedia(String contentHash) async {
    // Check local cache first
    final cached = CacheManager.instance.getCached(contentHash);
    if (cached != null) return cached;

    // TODO: dht.findProviders(cid) → peer list
    // TODO: bitswap.get(cid) → blocks → reassemble File
    // TODO: verify SHA-256 of reassembled bytes matches contentHash
    return null;
  }

  // ── Deletion / revocation ─────────────────────────────────────────────────

  /// Drops a cached file from local storage when a revocation is received.
  ///
  /// Spec v1.4 §12 "Deletion Flow" step 3: swarm participants are encouraged
  /// to delete local cache copies.
  Future<void> dropFromCache(String contentHash) async {
    await CacheManager.instance.purgeCached(contentHash);
    // TODO: bitswap unprovide(cid) — stop announcing this content to peers
    if (_seedingCount > 0) _seedingCount--;
  }

  // ── Status ────────────────────────────────────────────────────────────────

  int get seedingCount => _seedingCount;
  int get peerCount => 0; // TODO: return libp2p connected peer count
  bool get isRunning => _started;
  bool get isSeeding => _seedingCount > 0;

  /// Current on-device cache size in bytes.
  int get cacheSizeBytes => CacheManager.instance.totalCacheBytes;

  // ── Private helpers ───────────────────────────────────────────────────────

  /// Returns true when the device is connected via WiFi.
  ///
  /// Stub: always returns true.
  /// TODO: Use connectivity_plus package to check actual network type.
  ///       Only seed on WiFi to avoid unexpected mobile data usage.
  Future<bool> _isOnWifi() async {
    // TODO: final info = await Connectivity().checkConnectivity();
    //       return info == ConnectivityResult.wifi;
    return true;
  }
}
