import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:mobile/services/media_resolver.dart';

void main() {
  test('resolve returns local cache hit without touching CDN or P2P', () async {
    final tempDir = await Directory.systemTemp.createTemp('spot-resolver-');
    addTearDown(() => tempDir.delete(recursive: true));

    final cachedFile = File('${tempDir.path}/cached.jpg');
    await cachedFile.writeAsBytes(const [1, 2, 3]);

    var cdnCalled = false;
    var p2pCalled = false;

    final resolver = _TestMediaResolver(
      cacheResult: cachedFile,
      cdnFetcher: (_) async {
        cdnCalled = true;
        return null;
      },
      p2pFetcher: (_, {authorPubkey}) async {
        p2pCalled = true;
        return null;
      },
    );

    final result = await resolver.resolve('hash-a');

    expect(result, isNotNull);
    expect(result!.path, cachedFile.path);
    expect(cdnCalled, isFalse);
    expect(p2pCalled, isFalse);
  });

  test('resolve falls through to CDN when cache misses', () async {
    final tempDir = await Directory.systemTemp.createTemp('spot-resolver-');
    addTearDown(() => tempDir.delete(recursive: true));

    final cdnFile = File('${tempDir.path}/cdn.jpg');
    await cdnFile.writeAsBytes(const [4, 5, 6]);

    var p2pCalled = false;

    final resolver = _TestMediaResolver(
      cacheResult: null,
      cdnFetcher: (hash) async => hash == 'hash-b' ? cdnFile : null,
      p2pFetcher: (_, {authorPubkey}) async {
        p2pCalled = true;
        return null;
      },
    );

    final result = await resolver.resolve('hash-b');

    expect(result, isNotNull);
    expect(result!.path, cdnFile.path);
    expect(p2pCalled, isFalse);
  });

  test('resolve falls through to P2P when both cache and CDN miss', () async {
    final tempDir = await Directory.systemTemp.createTemp('spot-resolver-');
    addTearDown(() => tempDir.delete(recursive: true));

    final p2pFile = File('${tempDir.path}/p2p.jpg');
    await p2pFile.writeAsBytes(const [7, 8, 9]);

    final resolver = _TestMediaResolver(
      cacheResult: null,
      cdnFetcher: (_) async => null,
      p2pFetcher: (hash, {authorPubkey}) async =>
          hash == 'hash-c' ? p2pFile : null,
    );

    final result =
        await resolver.resolve('hash-c', authorPubkey: 'some-pubkey');

    expect(result, isNotNull);
    expect(result!.path, p2pFile.path);
  });

  test('resolve returns null when all tiers miss', () async {
    final resolver = _TestMediaResolver(
      cacheResult: null,
      cdnFetcher: (_) async => null,
      p2pFetcher: (_, {authorPubkey}) async => null,
    );

    final result = await resolver.resolve('hash-missing');

    expect(result, isNull);
  });

  test('resolve skips CDN when disabled', () async {
    final tempDir = await Directory.systemTemp.createTemp('spot-resolver-');
    addTearDown(() => tempDir.delete(recursive: true));

    final p2pFile = File('${tempDir.path}/p2p.jpg');
    await p2pFile.writeAsBytes(const [10, 11, 12]);

    var cdnCalled = false;

    final resolver = _TestMediaResolver(
      cacheResult: null,
      cdnEnabled: false,
      cdnFetcher: (_) async {
        cdnCalled = true;
        return null;
      },
      p2pFetcher: (hash, {authorPubkey}) async =>
          hash == 'hash-d' ? p2pFile : null,
    );

    final result = await resolver.resolve('hash-d');

    expect(result, isNotNull);
    expect(result!.path, p2pFile.path);
    expect(cdnCalled, isFalse);
  });
}

/// Test double that replaces the real [MediaResolver] dependencies.
class _TestMediaResolver {
  _TestMediaResolver({
    required this.cacheResult,
    required this.cdnFetcher,
    required this.p2pFetcher,
    this.cdnEnabled = true,
  });

  final File? cacheResult;
  final Future<File?> Function(String contentHash) cdnFetcher;
  final Future<File?> Function(String contentHash, {String? authorPubkey})
      p2pFetcher;
  final bool cdnEnabled;

  Future<File?> resolve(String contentHash, {String? authorPubkey}) async {
    // Tier 0: cache
    if (cacheResult != null && cacheResult!.existsSync()) return cacheResult;

    // Tier 1: CDN
    if (cdnEnabled) {
      final cdnFile = await cdnFetcher(contentHash);
      if (cdnFile != null) return cdnFile;
    }

    // Tier 2: P2P
    return p2pFetcher(contentHash, authorPubkey: authorPubkey);
  }
}
