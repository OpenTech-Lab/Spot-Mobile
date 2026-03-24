import 'dart:io';

import 'package:mobile/models/media_post.dart';

typedef MediaFetcher =
    Future<File?> Function(String contentHash, {String? authorPubkey});

class MediaSyncService {
  const MediaSyncService({required this.fetchMedia});

  final MediaFetcher fetchMedia;

  Future<List<MediaPost>> hydratePosts(Iterable<MediaPost> posts) async {
    final updatedPosts = <MediaPost>[];

    for (final post in posts) {
      final hydrated = await hydratePost(post);
      if (_pathsDiffer(post.mediaPaths, hydrated.mediaPaths)) {
        updatedPosts.add(hydrated);
      }
    }

    return updatedPosts;
  }

  Future<MediaPost> hydratePost(MediaPost post) async {
    if (post.isTextOnly || post.contentHashes.isEmpty) return post;

    final resolvedPaths = <String>[];
    var fetchedAny = false;

    for (var i = 0; i < post.contentHashes.length; i++) {
      final existingPath = i < post.mediaPaths.length
          ? post.mediaPaths[i]
          : null;
      if (existingPath != null && File(existingPath).existsSync()) {
        resolvedPaths.add(existingPath);
        continue;
      }

      final fetched = await fetchMedia(
        post.contentHashes[i],
        authorPubkey: post.pubkey,
      );
      if (fetched != null && fetched.existsSync()) {
        resolvedPaths.add(fetched.path);
        fetchedAny = true;
      }
    }

    if (!fetchedAny) return post;
    return post.copyWith(mediaPaths: resolvedPaths);
  }

  bool _pathsDiffer(List<String> before, List<String> after) {
    if (before.length != after.length) return true;
    for (var i = 0; i < before.length; i++) {
      if (before[i] != after[i]) return true;
    }
    return false;
  }
}
