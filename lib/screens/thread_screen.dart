import 'dart:async';
import 'dart:io';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import 'package:mobile/features/event/event_repository.dart';
import 'package:mobile/features/metadata/metadata_service.dart';
import 'package:mobile/features/p2p/p2p_service.dart';
import 'package:mobile/models/media_post.dart';
import 'package:mobile/models/wallet_model.dart';
import 'package:mobile/screens/discover_screen.dart';
import 'package:mobile/screens/post_composer_screen.dart';
import 'package:mobile/screens/user_profile_screen.dart';
import 'package:mobile/services/local_post_store.dart';
import 'package:mobile/services/media_resolver.dart';
import 'package:mobile/services/media_sync_service.dart';
import 'package:mobile/services/post_merge.dart';
import 'package:mobile/services/post_thread_ordering.dart';
import 'package:mobile/theme/spot_theme.dart';
import 'package:mobile/widgets/post_thread_row.dart';

Route<void> buildThreadScreenRoute({
  required String rootPostId,
  required List<MediaPost> initialPosts,
  required WalletModel wallet,
  EventRepository? eventRepo,
  MediaFetcher? mediaFetcher,
  Future<List<MediaPost>> Function()? persistedPostsLoader,
}) {
  return CupertinoPageRoute<void>(
    builder: (_) => ThreadScreen(
      rootPostId: rootPostId,
      initialPosts: initialPosts,
      wallet: wallet,
      eventRepo: eventRepo,
      mediaFetcher: mediaFetcher,
      persistedPostsLoader: persistedPostsLoader,
    ),
  );
}

Future<List<MediaPost>> mergeThreadPostsWithPersistedState({
  required List<MediaPost> initialPosts,
  required Future<List<MediaPost>> Function() loadPersistedPosts,
}) async {
  final persisted = await loadPersistedPosts();
  if (persisted.isEmpty) return List<MediaPost>.from(initialPosts);
  return mergePostsPreservingLocalState(initialPosts, persisted);
}

bool postNeedsMediaHydration(MediaPost post) {
  if (post.isTextOnly || post.contentHashes.isEmpty) return false;
  for (var i = 0; i < post.contentHashes.length; i++) {
    if (i >= post.mediaPaths.length || !File(post.mediaPaths[i]).existsSync()) {
      return true;
    }
  }
  return false;
}

class ThreadScreen extends StatefulWidget {
  const ThreadScreen({
    super.key,
    required this.rootPostId,
    required this.initialPosts,
    required this.wallet,
    this.eventRepo,
    this.mediaFetcher,
    this.persistedPostsLoader,
  });

  final String rootPostId;
  final List<MediaPost> initialPosts;
  final WalletModel wallet;
  final EventRepository? eventRepo;
  final MediaFetcher? mediaFetcher;
  final Future<List<MediaPost>> Function()? persistedPostsLoader;

  @override
  State<ThreadScreen> createState() => _ThreadScreenState();
}

class _ThreadScreenState extends State<ThreadScreen> {
  late List<MediaPost> _posts;
  final Set<String> _loadingMediaPostIds = {};

  @override
  void initState() {
    super.initState();
    _posts = List<MediaPost>.from(widget.initialPosts);
    unawaited(_primeThreadPosts());
  }

  List<ThreadedPostEntry> get _entries =>
      threadEntriesForRoot(_posts, widget.rootPostId);

  MediaPost? get _rootPost {
    for (final post in _posts) {
      if (post.nostrEventId == widget.rootPostId) return post;
    }
    return null;
  }

  void _openUserProfile(BuildContext ctx, String pubkey) {
    if (pubkey == widget.wallet.publicKeyHex) return;
    Navigator.of(ctx).push(
      MaterialPageRoute(
        builder: (_) =>
            UserProfileScreen(pubkey: pubkey, wallet: widget.wallet),
      ),
    );
  }

  void _openDiscoverTag(BuildContext ctx, String tag) {
    Navigator.of(ctx).push(
      buildDiscoverScreenRoute(
        wallet: widget.wallet,
        initialSearchQuery: '#$tag',
      ),
    );
  }

  Future<void> _reportPost(MediaPost post) async {
    try {
      await MetadataService.instance.reportContent(
        postId: post.nostrEventId,
        contentHash: post.contentHash,
        reason: 'harmful',
        wallet: widget.wallet,
      );
      if (!mounted) return;
      setState(() {
        _posts = _posts.where((candidate) => candidate.id != post.id).toList();
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Reported. Content hidden.')),
      );
    } catch (_) {}
  }

  void _mergePost(MediaPost post) {
    setState(() => _posts = mergePostsPreservingLocalState(_posts, [post]));
  }

  void _toggleLike(MediaPost post) {
    final updated = post.copyWith(isLikedByMe: !post.isLikedByMe);
    setState(() => _posts = replacePostsById(_posts, [updated]));
    unawaited(LocalPostStore.instance.setLikedByMe(post, updated.isLikedByMe));
  }

  void _updateMediaPost(MediaPost post) {
    setState(() {
      _posts = replacePostsById(_posts, [post]);
      _loadingMediaPostIds.remove(post.id);
    });
    unawaited(LocalPostStore.instance.savePost(post));
  }

  Future<void> _hydrateMediaPost(MediaPost post) async {
    if (_loadingMediaPostIds.contains(post.id)) return;
    setState(() => _loadingMediaPostIds.add(post.id));

    try {
      await P2PService.instance.startSwarm();
      final sync = MediaSyncService(
        fetchMedia: widget.mediaFetcher ?? MediaResolver.instance.resolve,
      );
      final hydrated = await sync.hydratePost(post);

      if (!mounted) return;
      _updateMediaPost(hydrated);
    } catch (_) {
      if (mounted) {
        setState(() => _loadingMediaPostIds.remove(post.id));
      }
    }
  }

  Future<void> _primeThreadPosts() async {
    await _restorePersistedPosts();
    await _syncThreadMedia();
  }

  Future<void> _restorePersistedPosts() async {
    final restored = await mergeThreadPostsWithPersistedState(
      initialPosts: _posts,
      loadPersistedPosts:
          widget.persistedPostsLoader ?? LocalPostStore.instance.loadPosts,
    );
    if (!mounted) return;
    setState(() => _posts = restored);
  }

  Future<void> _syncThreadMedia() async {
    final candidates = _entries
        .map((entry) => entry.post)
        .where(postNeedsMediaHydration)
        .toList(growable: false);
    if (!mounted || candidates.isEmpty) return;

    await P2PService.instance.startSwarm();
    final sync = MediaSyncService(
      fetchMedia: widget.mediaFetcher ?? MediaResolver.instance.resolve,
    );

    setState(() {
      _loadingMediaPostIds.addAll(candidates.map((post) => post.id));
    });

    for (final post in candidates) {
      final hydrated = await sync.hydratePost(post);
      if (!mounted) return;

      if (hydrated.mediaPaths.length != post.mediaPaths.length ||
          !_samePaths(hydrated.mediaPaths, post.mediaPaths)) {
        _updateMediaPost(hydrated);
      } else {
        setState(() => _loadingMediaPostIds.remove(post.id));
      }
    }
  }

  bool _samePaths(List<String> left, List<String> right) {
    if (left.length != right.length) return false;
    for (var i = 0; i < left.length; i++) {
      if (left[i] != right[i]) return false;
    }
    return true;
  }

  @override
  Widget build(BuildContext context) {
    final entries = _entries;
    final rootPost = _rootPost;
    final categoryTag = rootPost?.eventTags.isNotEmpty == true
        ? rootPost!.eventTags.first
        : null;
    final title = categoryTag != null ? '#$categoryTag' : 'Thread';

    return Scaffold(
      backgroundColor: SpotColors.bg,
      appBar: AppBar(
        backgroundColor: SpotColors.bg,
        title: Text(title, style: SpotType.subheading),
      ),
      body: entries.isEmpty
          ? const Center(
              child: Text(
                'Thread not available',
                style: SpotType.bodySecondary,
              ),
            )
          : ListView.builder(
              padding: const EdgeInsets.only(
                top: SpotSpacing.sm,
                bottom: SpotSpacing.xl,
              ),
              itemCount: entries.length,
              itemBuilder: (ctx, i) {
                final post = entries[i].post;
                return PostThreadRow(
                  post: post,
                  isLast: i == entries.length - 1,
                  isMediaLoading: _loadingMediaPostIds.contains(post.id),
                  onAvatarTap: () => _openUserProfile(ctx, post.pubkey),
                  onTagTap: (tag) => _openDiscoverTag(ctx, tag),
                  onReport: () => _reportPost(post),
                  onLike: () => _toggleLike(post),
                  onMediaUpdated: _hydrateMediaPost,
                  onReply: () => showPostComposer(
                    ctx,
                    wallet: widget.wallet,
                    eventRepo: widget.eventRepo,
                    replyToPost: post,
                    onPublished: _mergePost,
                  ),
                );
              },
            ),
    );
  }
}
