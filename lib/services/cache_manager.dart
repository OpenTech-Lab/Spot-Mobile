import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

/// Manages on-device media cache and content blocklist.
///
/// Spec v1.4 §6: hard cap 5 GB per app, auto-cleanup of old/non-pinned files.
/// Spec v1.4 §12.B: client-side blocklist — blocked content is never shown.
///
/// Initialise once at app start with [CacheManager.instance.init()].
class CacheManager {
  CacheManager._();

  static final CacheManager instance = CacheManager._();

  /// Maximum on-device cache size (5 GB per spec v1.4 §6).
  static const maxCacheSizeBytes = 5 * 1024 * 1024 * 1024;

  final Map<String, _CacheEntry> _entries = {};
  final Set<String> _blocklist = {};
  bool _initialised = false;

  // ── Init ──────────────────────────────────────────────────────────────────

  Future<void> init() async {
    if (_initialised) return;
    await Future.wait([_loadManifest(), _loadBlocklist()]);
    _initialised = true;
    await _evictIfNeeded();
  }

  // ── Cache tracking ────────────────────────────────────────────────────────

  /// Registers a newly captured/downloaded media file.
  Future<void> addToCache(String contentHash, String filePath) async {
    final file = File(filePath);
    final sizeBytes = file.existsSync() ? await file.length() : 0;
    _entries[contentHash] = _CacheEntry(
      path: filePath,
      sizeBytes: sizeBytes,
      accessedAt: DateTime.now(),
    );
    await _saveManifest();
    await _evictIfNeeded();
  }

  /// Returns the cached [File] for [contentHash], updating LRU timestamp.
  /// Returns null if not locally available.
  File? getCached(String contentHash) {
    final entry = _entries[contentHash];
    if (entry == null) return null;
    final file = File(entry.path);
    if (!file.existsSync()) {
      _entries.remove(contentHash);
      return null;
    }
    _entries[contentHash] = entry._withAccess(DateTime.now());
    _saveManifest(); // fire-and-forget
    return file;
  }

  /// Deletes a file from disk and removes it from the manifest.
  Future<void> purgeCached(String contentHash) async {
    final entry = _entries.remove(contentHash);
    if (entry != null) {
      final file = File(entry.path);
      if (file.existsSync()) {
        try {
          await file.delete();
        } catch (_) {}
      }
    }
    await _saveManifest();
  }

  /// Total bytes currently tracked in cache.
  int get totalCacheBytes =>
      _entries.values.fold(0, (sum, e) => sum + e.sizeBytes);

  // ── Blocklist ─────────────────────────────────────────────────────────────

  /// Returns true if [contentHash] is on the local blocklist.
  bool isBlocked(String contentHash) => _blocklist.contains(contentHash);

  /// Adds [contentHash] to the blocklist and purges local copy.
  /// Called on deletion/revocation and on user reports.
  Future<void> block(String contentHash) async {
    _blocklist.add(contentHash);
    await Future.wait([_saveBlocklist(), purgeCached(contentHash)]);
  }

  // ── Private: eviction ─────────────────────────────────────────────────────

  Future<void> _evictIfNeeded() async {
    if (totalCacheBytes <= maxCacheSizeBytes) return;

    // Sort LRU: oldest-accessed first
    final sorted = _entries.entries.toList()
      ..sort((a, b) => a.value.accessedAt.compareTo(b.value.accessedAt));

    for (final e in sorted) {
      if (totalCacheBytes <= maxCacheSizeBytes) break;
      await purgeCached(e.key);
    }
  }

  // ── Private: persistence ──────────────────────────────────────────────────

  Future<File> get _manifestFile async {
    final dir = await getApplicationDocumentsDirectory();
    return File('${dir.path}/cache_manifest.json');
  }

  Future<File> get _blocklistFile async {
    final dir = await getApplicationDocumentsDirectory();
    return File('${dir.path}/blocklist.json');
  }

  Future<void> _loadManifest() async {
    try {
      final file = await _manifestFile;
      if (!file.existsSync()) return;
      final json = jsonDecode(await file.readAsString()) as Map<String, dynamic>;
      for (final entry in json.entries) {
        _entries[entry.key] =
            _CacheEntry.fromJson(entry.value as Map<String, dynamic>);
      }
    } catch (_) {}
  }

  Future<void> _saveManifest() async {
    try {
      final file = await _manifestFile;
      await file.writeAsString(
        jsonEncode({
          for (final e in _entries.entries) e.key: e.value.toJson(),
        }),
      );
    } catch (_) {}
  }

  Future<void> _loadBlocklist() async {
    try {
      final file = await _blocklistFile;
      if (!file.existsSync()) return;
      final list = jsonDecode(await file.readAsString()) as List;
      _blocklist.addAll(list.cast<String>());
    } catch (_) {}
  }

  Future<void> _saveBlocklist() async {
    try {
      final file = await _blocklistFile;
      await file.writeAsString(jsonEncode(_blocklist.toList()));
    } catch (_) {}
  }
}

// ── Cache entry ───────────────────────────────────────────────────────────────

class _CacheEntry {
  const _CacheEntry({
    required this.path,
    required this.sizeBytes,
    required this.accessedAt,
  });

  final String path;
  final int sizeBytes;
  final DateTime accessedAt;

  _CacheEntry _withAccess(DateTime at) =>
      _CacheEntry(path: path, sizeBytes: sizeBytes, accessedAt: at);

  Map<String, dynamic> toJson() => {
        'path': path,
        'sizeBytes': sizeBytes,
        'accessedAt': accessedAt.toIso8601String(),
      };

  factory _CacheEntry.fromJson(Map<String, dynamic> json) => _CacheEntry(
        path: json['path'] as String,
        sizeBytes: (json['sizeBytes'] as num?)?.toInt() ?? 0,
        accessedAt: DateTime.parse(json['accessedAt'] as String),
      );
}
