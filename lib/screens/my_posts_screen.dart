import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import 'package:mobile/features/event/event_repository.dart';
import 'package:mobile/features/p2p/p2p_service.dart';
import 'package:mobile/models/event_model.dart';
import 'package:mobile/models/media_post.dart';
import 'package:mobile/models/wallet_model.dart';
import 'package:mobile/screens/discover_screen.dart';
import 'package:mobile/services/cache_manager.dart';
import 'package:mobile/services/local_post_store.dart';
import 'package:mobile/services/media_resolver.dart';
import 'package:mobile/services/media_sync_service.dart';
import 'package:mobile/services/post_merge.dart';
import 'package:mobile/services/post_thread_ordering.dart';
import 'package:mobile/theme/spot_theme.dart';
import 'package:mobile/widgets/post_thread_row.dart';

/// Shows only the posts authored by the current wallet owner.
class MyPostsScreen extends StatefulWidget {
  const MyPostsScreen({super.key, required this.wallet});

  final WalletModel wallet;

  @override
  State<MyPostsScreen> createState() => _MyPostsScreenState();
}

class _MyPostsScreenState extends State<MyPostsScreen> {
  late final EventRepository _repo;
  StreamSubscription<CivicEvent>? _sub;

  List<MediaPost> _posts = [];
  final Set<String> _loadingMediaPostIds = {};
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _repo = EventRepository();
    _initFeed();
  }

  @override
  void dispose() {
    _sub?.cancel();
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
      _sub = _repo.subscribeToEvents().listen(_onEvent);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _onEvent(CivicEvent event) {
    if (!mounted) return;
    final mine = event.posts
        .where((p) => p.pubkey == widget.wallet.publicKeyHex)
        .toList();
    if (mine.isEmpty) return;
    final merged = _mergePosts(_posts, mine);
    if (orderedPostsEqual(merged, _posts)) return;
    setState(() => _posts = merged);
  }

  Future<void> _refresh() async {
    await _sub?.cancel();
    setState(() => _posts = []);
    await _initFeed();
  }

  Future<void> _loadPersistedPosts() async {
    final persisted = await LocalPostStore.instance.loadPosts(
      authorPubkey: widget.wallet.publicKeyHex,
    );
    final visible = persisted
        .where(
          (post) => post.contentHashes.every(
            (hash) => !CacheManager.instance.isBlocked(hash),
          ),
        )
        .toList();
    if (!mounted || visible.isEmpty) return;
    setState(() => _posts = _mergePosts(_posts, visible));
  }

  List<MediaPost> _mergePosts(
    List<MediaPost> current,
    Iterable<MediaPost> incoming,
  ) => mergePostsPreservingLocalState(current, incoming);

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
        title: const Text('My Posts', style: SpotType.subheading),
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
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

    if (_posts.isEmpty) {
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
              'No posts yet',
              style: SpotType.bodySecondary.copyWith(
                fontWeight: FontWeight.w300,
              ),
            ),
            const SizedBox(height: SpotSpacing.xs),
            const Text(
              'Capture a moment to see it here',
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
          final entries = buildThreadedPostEntries(_posts);
          return ListView.builder(
            padding: const EdgeInsets.only(
              top: SpotSpacing.sm,
              bottom: SpotSpacing.xl,
            ),
            itemCount: entries.length,
            itemBuilder: (ctx, i) => PostThreadRow(
              post: entries[i].post,
              isLast: isLastInThread(entries, i),
              isMediaLoading: _loadingMediaPostIds.contains(entries[i].post.id),
              onTagTap: (tag) => _openDiscoverTag(ctx, tag),
              onLike: () => _toggleLike(entries[i].post),
              onMediaUpdated: _hydrateMediaPost,
            ),
          );
        },
      ),
    );
  }
}
