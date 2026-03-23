import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:mobile/models/media_post.dart';
import 'package:mobile/services/media_sync_service.dart';

void main() {
  test(
    'hydratePosts upgrades a remote post with fetched media paths',
    () async {
      final tempDir = await Directory.systemTemp.createTemp('spot-media-sync-');
      addTearDown(() => tempDir.delete(recursive: true));

      final fetchedFile = File('${tempDir.path}/media.jpg');
      await fetchedFile.writeAsBytes(const [1, 2, 3]);

      final service = MediaSyncService(
        fetchMedia: (contentHash) async {
          if (contentHash == 'hash-a') return fetchedFile;
          return null;
        },
      );

      final updated = await service.hydratePosts([
        _post(contentHashes: const ['hash-a']),
      ]);

      expect(updated, hasLength(1));
      expect(updated.single.mediaPaths, [fetchedFile.path]);
    },
  );

  test(
    'hydratePosts leaves posts unchanged when fetch returns nothing',
    () async {
      final service = MediaSyncService(fetchMedia: (_) async => null);

      final updated = await service.hydratePosts([
        _post(contentHashes: const ['hash-a']),
      ]);

      expect(updated, isEmpty);
    },
  );
}

MediaPost _post({required List<String> contentHashes}) => MediaPost(
  id: 'post-id',
  pubkey: 'pubkey',
  contentHashes: contentHashes,
  capturedAt: DateTime.utc(2026, 3, 23),
  eventTags: const ['tokyo'],
  nostrEventId: 'post-id',
);
