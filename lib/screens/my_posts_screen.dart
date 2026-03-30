import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import 'package:mobile/features/event/event_repository.dart';
import 'package:mobile/features/p2p/p2p_service.dart';
import 'package:mobile/models/media_post.dart';
import 'package:mobile/models/wallet_model.dart';
import 'package:mobile/screens/discover_screen.dart';
import 'package:mobile/services/app_data_reset_service.dart';
import 'package:mobile/services/cache_manager.dart';
import 'package:mobile/services/local_post_store.dart';
import 'package:mobile/services/media_resolver.dart';
import 'package:mobile/services/media_sync_service.dart';
import 'package:mobile/services/post_merge.dart';
import 'package:mobile/services/post_thread_ordering.dart';
import 'package:mobile/theme/spot_theme.dart';
import 'package:mobile/widgets/post_thread_row.dart';

enum MyPostsScreenMode { threads, replies }

/// Shows only the posts authored by the current wallet owner.
class MyPostsScreen extends StatefulWidget {
  const MyPostsScreen({
    super.key,
    required this.wallet,
    this.mode = MyPostsScreenMode.threads,
  });

  final WalletModel wallet;
  final MyPostsScreenMode mode;

  String get title => switch (mode) {
    MyPostsScreenMode.threads => 'Posted Threads',
    MyPostsScreenMode.replies => 'Replied Threads',
  };

  String get emptyTitle => switch (mode) {
    MyPostsScreenMode.threads => 'No threads yet',
    MyPostsScreenMode.replies => 'No replies yet',
  };

  String get emptySubtitle => switch (mode) {
    MyPostsScreenMode.threads => 'Threads you post publicly will appear here',
    MyPostsScreenMode.replies => 'Replies you post publicly will appear here',
  };

  @override
  State<MyPostsScreen> createState() => _MyPostsScreenState();
}

class _MyPostsScreenState extends State<MyPostsScreen> {
  late final EventRepository _repo;
  StreamSubscription<void>? _repoSub;
  StreamSubscription<void>? _resetSub;

  List<MediaPost> _posts = [];
  List<MediaPost> _remotePosts = [];
  List<MediaPost> _persistedPosts = [];
  final Set<String> _loadingMediaPostIds = {};
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _repo = EventRepository();
    _resetSub ??= AppDataResetService.instance.localDataCleared.listen((_) {
      unawaited(_handleLocalDataCleared());
    });
    _initFeed();
  }

  @override
  void dispose() {
    _repoSub?.cancel();
    _resetSub?.cancel();
    _repo.dispose();
    super.dispose();
  }

  Future<void> _initFeed() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      await _loadPersistedPosts();
      _repoSub ??= _repo
          .subscribeToAuthorChanges(widget.wallet.publicKeyHex)
          .listen((_) => _onRepoChanged());
      _onRepoChanged();
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _onRepoChanged() {
    if (!mounted) return;
    _remotePosts = _visibleRemotePosts(
      _repo.getPostsForAuthor(widget.wallet.publicKeyHex),
    );
    _syncVisiblePosts();
  }

  Future<void> _refresh() async {
    setState(() {
      _isLoading = true;
      _error = null;
      _remotePosts = [];
      _posts = [];
    });
    try {
      await _loadPersistedPosts();
      await _repo.refresh();
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _loadPersistedPosts() async {
    final persisted = await LocalPostStore.instance.loadPosts(
      authorPubkey: widget.wallet.publicKeyHex,
    );
    _persistedPosts = persisted
        .where(
          (post) => post.contentHashes.every(
            (hash) => !CacheManager.instance.isBlocked(hash),
          ),
        )
        .toList(growable: false);
    _syncVisiblePosts();
  }

  List<MediaPost> _visibleRemotePosts(Iterable<MediaPost> posts) {
    return posts
        .where(
          (post) => post.contentHashes.every(
            (hash) => !CacheManager.instance.isBlocked(hash),
          ),
        )
        .toList(growable: false);
  }

  void _syncVisiblePosts() {
    if (!mounted) return;
    final rebuilt = reconcilePostsPreservingLocalState(_posts, [
      _remotePosts,
      _persistedPosts,
    ]);
    if (orderedPostsEqual(rebuilt, _posts)) return;
    setState(() => _posts = rebuilt);
  }

  Future<void> _handleLocalDataCleared() async {
    if (!mounted) return;
    setState(() {
      _persistedPosts = [];
      _remotePosts = [];
      _posts = [];
    });
    try {
      await _repo.refresh();
    } catch (_) {}
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
      final sync = MediaSyncService(fetchMedia: MediaResolver.instance.resolve);
      final hydrated = await sync.hydratePost(post);

      if (!mounted) return;
      _updateMediaPost(hydrated);
    } catch (_) {
      if (mounted) {
        setState(() => _loadingMediaPostIds.remove(post.id));
      }
    }
  }

  void _openDiscoverTag(BuildContext context, String tag) {
    Navigator.of(context).push(
      buildDiscoverScreenRoute(
        wallet: widget.wallet,
        initialSearchQuery: '#$tag',
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: SpotColors.bg,
      appBar: AppBar(
        backgroundColor: SpotColors.bg,
        leading: IconButton(
          icon: const Icon(CupertinoIcons.chevron_back, size: 16),
          color: SpotColors.textSecondary,
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text(widget.title, style: SpotType.subheading),
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    final visiblePosts = switch (widget.mode) {
      MyPostsScreenMode.threads => topLevelThreadPosts(_posts),
      MyPostsScreenMode.replies => replyPosts(_posts),
    };

    if (_isLoading && _posts.isEmpty) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(
                color: SpotColors.accent,
                strokeWidth: 1,
              ),
            ),
            SizedBox(height: SpotSpacing.xl),
            Text('Loading', style: SpotType.label),
          ],
        ),
      );
    }

    if (_error != null && _posts.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(SpotSpacing.xxxl),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                CupertinoIcons.wifi_slash,
                color: SpotColors.textTertiary,
                size: 32,
              ),
              const SizedBox(height: SpotSpacing.xl),
              const Text('Could not load posts', style: SpotType.bodySecondary),
              const SizedBox(height: SpotSpacing.xl),
              GestureDetector(
                onTap: _refresh,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: SpotSpacing.xl,
                    vertical: SpotSpacing.sm,
                  ),
                  decoration: BoxDecoration(
                    border: Border.all(color: SpotColors.border, width: 0.5),
                    borderRadius: BorderRadius.circular(SpotRadius.sm),
                  ),
                  child: const Text('Retry', style: SpotType.bodySecondary),
                ),
              ),
            ],
          ),
        ),
      );
    }

    if (visiblePosts.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              CupertinoIcons.camera,
              color: SpotColors.overlay,
              size: 36,
            ),
            const SizedBox(height: SpotSpacing.lg),
            Text(
              widget.emptyTitle,
              style: SpotType.bodySecondary.copyWith(
                fontWeight: FontWeight.w300,
              ),
            ),
            const SizedBox(height: SpotSpacing.xs),
            Text(
              widget.emptySubtitle,
              style: SpotType.caption,
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      color: SpotColors.accent,
      backgroundColor: SpotColors.surface,
      displacement: 28,
      onRefresh: _refresh,
      child: Builder(
        builder: (ctx) {
          return ListView.builder(
            padding: const EdgeInsets.only(
              top: SpotSpacing.sm,
              bottom: SpotSpacing.xl,
            ),
            itemCount: visiblePosts.length,
            itemBuilder: (ctx, i) => PostThreadRow(
              post: visiblePosts[i],
              isLast: true,
              isMediaLoading: _loadingMediaPostIds.contains(visiblePosts[i].id),
              onTagTap: (tag) => _openDiscoverTag(ctx, tag),
              onLike: () => _toggleLike(visiblePosts[i]),
              onMediaUpdated: _hydrateMediaPost,
            ),
          );
        },
      ),
    );
  }
}
