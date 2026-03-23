import 'package:mobile/models/media_post.dart';

List<MediaPost> mergePostsPreservingLocalState(
  List<MediaPost> current,
  Iterable<MediaPost> incoming,
) {
  final byId = {for (final post in current) post.id: post};
  for (final post in incoming) {
    final existing = byId[post.id];
    byId[post.id] = existing == null
        ? post
        : post.mergeLocalStateFrom(existing);
  }
  return byId.values.toList()
    ..sort((a, b) => b.capturedAt.compareTo(a.capturedAt));
}

List<MediaPost> replacePostsById(
  List<MediaPost> current,
  Iterable<MediaPost> updates,
) {
  final byId = {for (final post in current) post.id: post};
  for (final post in updates) {
    byId[post.id] = post;
  }
  return byId.values.toList()
    ..sort((a, b) => b.capturedAt.compareTo(a.capturedAt));
}
