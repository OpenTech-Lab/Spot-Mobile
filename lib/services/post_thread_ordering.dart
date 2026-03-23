import 'package:mobile/models/media_post.dart';

typedef ThreadedPostEntry = ({int depth, MediaPost post, String rootId});

List<ThreadedPostEntry> buildThreadedPostEntries(Iterable<MediaPost> posts) {
  final postsByEventId = <String, MediaPost>{};
  for (final post in posts) {
    postsByEventId[post.nostrEventId] = post;
  }

  final childrenByParent = <String, List<MediaPost>>{};
  for (final post in postsByEventId.values) {
    final parentId = post.replyToId;
    if (parentId == null) continue;
    childrenByParent.putIfAbsent(parentId, () => []).add(post);
  }

  final visibleIds = postsByEventId.keys.toSet();
  final latestActivityCache = <String, DateTime>{};

  DateTime latestActivity(MediaPost post) {
    final cached = latestActivityCache[post.nostrEventId];
    if (cached != null) return cached;

    var latest = post.capturedAt;
    for (final child in childrenByParent[post.nostrEventId] ?? const []) {
      final childLatest = latestActivity(child);
      if (childLatest.isAfter(latest)) latest = childLatest;
    }
    latestActivityCache[post.nostrEventId] = latest;
    return latest;
  }

  int newestFirst(MediaPost a, MediaPost b) {
    final byActivity = latestActivity(b).compareTo(latestActivity(a));
    if (byActivity != 0) return byActivity;
    return b.capturedAt.compareTo(a.capturedAt);
  }

  final roots =
      postsByEventId.values
          .where(
            (post) =>
                post.replyToId == null || !visibleIds.contains(post.replyToId),
          )
          .toList()
        ..sort(newestFirst);

  final ordered = <ThreadedPostEntry>[];
  final visited = <String>{};

  void append(MediaPost post, {required int depth, required String rootId}) {
    if (!visited.add(post.nostrEventId)) return;

    ordered.add((depth: depth, post: post, rootId: rootId));

    final replies = [...?childrenByParent[post.nostrEventId]]
      ..sort((a, b) => a.capturedAt.compareTo(b.capturedAt));
    for (final reply in replies) {
      append(reply, depth: depth + 1, rootId: rootId);
    }
  }

  for (final root in roots) {
    append(root, depth: 0, rootId: root.nostrEventId);
  }

  final dangling =
      postsByEventId.values
          .where((post) => !visited.contains(post.nostrEventId))
          .toList()
        ..sort(newestFirst);
  for (final post in dangling) {
    append(post, depth: 0, rootId: post.nostrEventId);
  }

  return ordered;
}

bool isLastInThread(List<ThreadedPostEntry> entries, int index) {
  if (index >= entries.length - 1) return true;
  return entries[index].rootId != entries[index + 1].rootId;
}
