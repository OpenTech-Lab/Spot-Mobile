import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:mobile/core/encryption.dart';
import 'package:mobile/models/asset_transport_policy.dart';
import 'package:mobile/features/p2p/p2p_service.dart';
import 'package:mobile/services/cache_manager.dart';

void main() {
  test('P2PService serves seeded media over its local HTTP endpoint', () async {
    final tempDir = await Directory.systemTemp.createTemp('spot-p2p-seed-');
    final service = P2PService.forTesting(
      localEndpointResolver: (port) async => [
        Uri.parse('http://127.0.0.1:$port'),
      ],
      tempDirLoader: () async => tempDir,
      transportPolicyGetter: () => AssetTransportPolicy.always,
      wifiChecker: () async => true,
    );
    addTearDown(() async {
      await service.stopSwarm();
      await tempDir.delete(recursive: true);
    });

    final file = File('${tempDir.path}/photo.jpg');
    final bytes = Uint8List.fromList(
      List<int>.generate(512, (index) => (index * 7) % 256),
    );
    await file.writeAsBytes(bytes);
    final contentHash = EncryptionUtils.sha256BytesHex(bytes);

    await service.startSwarm();
    await service.seedMedia(file.path, contentHash);

    final client = HttpClient();
    addTearDown(() => client.close(force: true));
    final request = await client.getUrl(
      service.localEndpoints.single.replace(path: '/media/$contentHash'),
    );
    final response = await request.close();
    final downloaded = await consolidateHttpClientResponseBytes(response);

    expect(response.statusCode, HttpStatus.ok);
    expect(downloaded, bytes);
  });

  test('P2PService requestMedia downloads and caches remote media', () async {
    final tempDir = await Directory.systemTemp.createTemp('spot-p2p-fetch-');
    addTearDown(() => tempDir.delete(recursive: true));

    final file = File('${tempDir.path}/photo.jpg');
    final bytes = Uint8List.fromList(
      List<int>.generate(1024, (index) => (index * 13) % 256),
    );
    await file.writeAsBytes(bytes);
    final contentHash = EncryptionUtils.sha256BytesHex(bytes);

    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    unawaited(
      server.forEach((request) async {
        if (request.uri.path == '/media/$contentHash') {
          request.response.headers.set('x-spot-file-name', 'photo.jpg');
          request.response.headers.set(
            HttpHeaders.contentTypeHeader,
            'image/jpeg',
          );
          request.response.add(bytes);
        } else {
          request.response.statusCode = HttpStatus.notFound;
        }
        await request.response.close();
      }),
    );

    final service = P2PService.forTesting(
      peerEndpointResolver: (_) async => [
        Uri.parse('http://127.0.0.1:${server.port}'),
      ],
      tempDirLoader: () async => tempDir,
      transportPolicyGetter: () => AssetTransportPolicy.always,
      wifiChecker: () async => true,
    );

    final fetched = await service.requestMedia(
      contentHash,
      authorPubkey: 'peer-pubkey',
    );

    expect(fetched, isNotNull);
    expect(await fetched!.readAsBytes(), bytes);
    expect(CacheManager.instance.getCached(contentHash)?.path, fetched.path);
  });

  test(
    'P2PService does not start transport on Wi-Fi only policy off Wi-Fi',
    () async {
      final service = P2PService.forTesting(
        localEndpointResolver: (port) async => [
          Uri.parse('http://127.0.0.1:$port'),
        ],
        transportPolicyGetter: () => AssetTransportPolicy.wifiOnly,
        wifiChecker: () async => false,
      );
      addTearDown(() => service.shutdown());

      await service.startSwarm();

      expect(service.isRunning, isFalse);
      expect(service.localEndpoints, isEmpty);
    },
  );

  test('P2PService requestMedia respects disabled transport policy', () async {
    var endpointLookups = 0;
    final service = P2PService.forTesting(
      peerEndpointResolver: (_) async {
        endpointLookups++;
        return [Uri.parse('http://127.0.0.1:1')];
      },
      transportPolicyGetter: () => AssetTransportPolicy.off,
    );

    final fetched = await service.requestMedia(
      'missing-hash',
      authorPubkey: 'peer-pubkey',
    );

    expect(fetched, isNull);
    expect(endpointLookups, 0);
  });

  test(
    'P2PService refreshTransportAvailability starts once Wi-Fi is available',
    () async {
      var onWifi = false;
      final service = P2PService.forTesting(
        localEndpointResolver: (port) async => [
          Uri.parse('http://127.0.0.1:$port'),
        ],
        transportPolicyGetter: () => AssetTransportPolicy.wifiOnly,
        wifiChecker: () async => onWifi,
      );
      addTearDown(() => service.shutdown());

      await service.refreshTransportAvailability();
      expect(service.isRunning, isFalse);

      onWifi = true;
      await service.refreshTransportAvailability();

      expect(service.isRunning, isTrue);
      expect(service.localEndpoints, isNotEmpty);
    },
  );
}
