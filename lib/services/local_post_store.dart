import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import 'package:mobile/models/media_post.dart';

/// Persists locally-seen posts so feed metadata survives app reloads even
/// before relays re-deliver the same events from history.
class LocalPostStore {
  LocalPostStore._();

  static final LocalPostStore instance = LocalPostStore._();

  Future<List<MediaPost>> loadPosts({String? authorPubkey}) async {
    final posts = await _readPosts();
    final filtered = authorPubkey == null
        ? posts
        : posts.where((post) => post.pubkey == authorPubkey).toList();
    filtered.sort((a, b) => b.capturedAt.compareTo(a.capturedAt));
    return filtered;
  }

  Future<void> savePost(MediaPost post) async {
    await savePosts([post]);
  }

  Future<void> savePosts(Iterable<MediaPost> incoming) async {
    final posts = await _readPosts();
    final byId = {for (final existing in posts) existing.id: existing};
    for (final post in incoming) {
      final existing = byId[post.id];
      byId[post.id] = existing == null
          ? post
          : post.mergeLocalStateFrom(existing);
    }
    await _writePosts(byId.values);
  }

  Future<MediaPost> setLikedByMe(MediaPost post, bool isLikedByMe) async {
    final updated = post.copyWith(isLikedByMe: isLikedByMe);
    final posts = await _readPosts();
    final byId = {for (final existing in posts) existing.id: existing};
    byId[updated.id] = updated;
    await _writePosts(byId.values);
    return updated;
  }

  Future<void> removePost(String postId) async {
    final posts = await _readPosts();
    posts.removeWhere((post) => post.id == postId);
    await _writePosts(posts);
  }

  Future<File> get _storeFile async {
    final dir = await getApplicationDocumentsDirectory();
    return File('${dir.path}/local_posts.json');
  }

  Future<List<MediaPost>> _readPosts() async {
    try {
      final file = await _storeFile;
      if (!file.existsSync()) return [];
      final raw = await file.readAsString();
      if (raw.trim().isEmpty) return [];
      final decoded = jsonDecode(raw) as List;
      return decoded
          .whereType<Map<String, dynamic>>()
          .map(MediaPost.fromJson)
          .toList();
    } catch (_) {
      return [];
    }
  }

  Future<void> _writePosts(Iterable<MediaPost> posts) async {
    final sorted = posts.toList()
      ..sort((a, b) => b.capturedAt.compareTo(a.capturedAt));
    final file = await _storeFile;
    await file.writeAsString(
      jsonEncode(sorted.map((post) => post.toJson()).toList()),
    );
  }
}
