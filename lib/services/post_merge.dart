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

List<MediaPost> reconcilePostsPreservingLocalState(
  List<MediaPost> current,
  Iterable<Iterable<MediaPost>> sources,
) {
  final currentById = {for (final post in current) post.id: post};
  final nextById = <String, MediaPost>{};

  for (final source in sources) {
    for (final post in source) {
      final existing = nextById[post.id] ?? currentById[post.id];
      nextById[post.id] = existing == null
          ? post
          : post.mergeLocalStateFrom(existing);
    }
  }

  return nextById.values.toList()
    ..sort((a, b) => b.capturedAt.compareTo(a.capturedAt));
}

bool orderedPostsEqual(List<MediaPost> current, List<MediaPost> incoming) {
  if (current.length != incoming.length) return false;
  for (var i = 0; i < current.length; i++) {
    if (!current[i].isEquivalentTo(incoming[i])) return false;
  }
  return true;
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
