import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import 'package:mobile/features/event/event_repository.dart';
import 'package:mobile/features/nostr/nostr_service.dart';
import 'package:mobile/models/event_model.dart';
import 'package:mobile/models/media_post.dart';
import 'package:mobile/models/wallet_model.dart';
import 'package:mobile/screens/interests_screen.dart';
import 'package:mobile/screens/post_composer_screen.dart';
import 'package:mobile/screens/thread_screen.dart';
import 'package:mobile/screens/user_profile_screen.dart';
import 'package:mobile/services/cache_manager.dart';
import 'package:mobile/features/p2p/p2p_service.dart';
import 'package:mobile/services/media_resolver.dart';
import 'package:mobile/services/media_sync_service.dart';
import 'package:mobile/services/follow_service.dart';
import 'package:mobile/services/local_post_store.dart';
import 'package:mobile/services/post_merge.dart';
import 'package:mobile/services/post_thread_ordering.dart';
import 'package:mobile/services/user_prefs_service.dart';
import 'package:mobile/theme/spot_theme.dart';
import 'package:mobile/widgets/post_thread_row.dart';

/// Home feed — LATEST (real-time) and FOLLOWING (people you follow).
List<MediaPost> visibleFollowingPosts(
  Iterable<MediaPost> posts, {
  required String selfPubkey,
  required Set<String> followedPubkeys,
  required Set<String> followedTags,
}) {
  return posts
      .where(
        (post) =>
            post.pubkey == selfPubkey ||
            followedPubkeys.contains(post.pubkey) ||
            post.eventTags.any(followedTags.contains),
      )
      .toList(growable: false);
}

class FeedScreen extends StatefulWidget {
  const FeedScreen({
    super.key,
    required this.nostrService,
    required this.wallet,
    required this.eventRepo,
  });

  final NostrService nostrService;
  final WalletModel wallet;
  final EventRepository eventRepo;

  @override
  State<FeedScreen> createState() => FeedScreenState();
}

class FeedScreenState extends State<FeedScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;
  EventRepository get _repo => widget.eventRepo;
  StreamSubscription<CivicEvent>? _sub;

  List<MediaPost> _posts = [];
  final Set<String> _loadingMediaPostIds = {};
  bool _isLoading = true;
  String? _error;

  // Infinite scroll (Latest tab)
  bool _isFetchingMore = false;
  int? _oldestTimestamp;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    FollowService.instance.init();
    _initFeed();
    _showInterestsIfNeeded();
  }

  @override
  void dispose() {
    _tabController.dispose();
    _sub?.cancel();
    super.dispose();
  }

  // ── Public API ────────────────────────────────────────────────────────────

  /// Called externally (e.g. double-tap on Home nav icon) to reload the feed.
  void triggerRefresh() => _refresh();

  /// Called externally after a successful publish so Home can show the new
  /// thread immediately instead of waiting for the repository stream.
  void showPublishedPost(MediaPost post) {
    if (!mounted) return;
    debugPrint('[FeedScreen] showPublishedPost called for ${post.id}');
    setState(() {
      _posts = _mergePosts(_posts, [post]);
    });
    debugPrint('[FeedScreen] Total posts after showPublishedPost: ${_posts.length}');
    if (_tabController.index != 0) {
      _tabController.animateTo(0);
    }
  }

  // ── Data loading ──────────────────────────────────────────────────────────

  Future<void> _initFeed() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      await _loadPersistedPosts();
      await widget.nostrService.connect();
      _sub = _repo.subscribeToEvents().listen(_onEvent);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _onEvent(CivicEvent event) {
    if (!mounted) return;
    debugPrint('[FeedScreen] Received CivicEvent: ${event.hashtag}, ${event.posts.length} posts');
    setState(() {
      _posts = _mergePosts(_posts, event.posts);
    });
    debugPrint('[FeedScreen] Total posts after merge: ${_posts.length}');
    unawaited(LocalPostStore.instance.savePosts(event.posts));
  }

  Future<void> _refresh() async {
    await _sub?.cancel();
    _repo.reset();
    _oldestTimestamp = null;
    setState(() => _posts = []);
    await _initFeed();
  }

  Future<void> _loadPersistedPosts() async {
    final persisted = await LocalPostStore.instance.loadPosts();
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

  Future<void> _loadMorePosts() async {
    if (_isFetchingMore || _posts.isEmpty) return;

    final cursor =
        _oldestTimestamp ??
        (_posts.last.capturedAt.millisecondsSinceEpoch ~/ 1000) - 1;

    setState(() => _isFetchingMore = true);
    try {
      final completer = Completer<void>();
      Timer? timeout;

      final subId = widget.nostrService.subscribe(
        EventRepository.buildSpotPostFilters(
          until: cursor,
          limit: 20,
          includeGenericFallback: true,
        ),
        (event) {
          if (!EventRepository.isSpotEvent(event)) return;
          _repo.addPost(EventRepository.nostrEventToPost(event));
        },
      );

      timeout = Timer(const Duration(seconds: 5), () {
        widget.nostrService.unsubscribe(subId);
        if (!completer.isCompleted) completer.complete();
      });

      await completer.future;
      timeout.cancel();
      widget.nostrService.unsubscribe(subId);

      if (mounted) {
        final allPosts = _repo.getAllEvents().expand((e) => e.posts).toList()
          ..sort((a, b) => b.capturedAt.compareTo(a.capturedAt));
        final merged = _mergePosts(_posts, allPosts);
        if (merged.isNotEmpty) {
          _oldestTimestamp =
              (merged.last.capturedAt.millisecondsSinceEpoch ~/ 1000) - 1;
        }
        setState(() => _posts = merged);
      }
    } finally {
      if (mounted) setState(() => _isFetchingMore = false);
    }
  }

  List<MediaPost> _mergePosts(
    List<MediaPost> current,
    Iterable<MediaPost> incoming,
  ) {
    debugPrint('[FeedScreen] _mergePosts: ${current.length} current + ${incoming.length} incoming');
    for (final post in incoming) {
      debugPrint('[FeedScreen] Incoming post: ${post.id}, tags: ${post.eventTags}');
      final isBlocked = CacheManager.instance.isBlocked(post.contentHash);
      debugPrint('[FeedScreen] Post ${post.id} blocked: $isBlocked, contentHash: ${post.contentHash}');
    }
    final result = mergePostsPreservingLocalState(
      current,
      incoming.where(
        (post) => !CacheManager.instance.isBlocked(post.contentHash),
      ),
    );
    debugPrint('[FeedScreen] _mergePosts result: ${result.length} posts');
    return result;
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

  Future<void> _reportPost(MediaPost post) async {
    try {
      await widget.nostrService.reportContent(
        eventId: post.nostrEventId,
        contentHash: post.contentHash,
        reason: 'harmful',
        wallet: widget.wallet,
      );
      setState(() => _posts = _posts.where((p) => p.id != post.id).toList());
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Reported. Content hidden.')),
        );
      }
    } catch (_) {}
  }

  Future<void> _showInterestsIfNeeded() async {
    await UserPrefsService.instance.init();
    if (UserPrefsService.instance.hasSetInterests) return;
    if (!mounted) return;
    await Future<void>.delayed(const Duration(milliseconds: 600));
    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => InterestsScreen(onDone: () => setState(() {})),
    );
  }

  void _openUserProfile(BuildContext ctx, String pubkey) {
    if (pubkey == widget.wallet.publicKeyHex) return;
    Navigator.of(ctx).push(
      MaterialPageRoute(
        builder: (_) => UserProfileScreen(
          pubkey: pubkey,
          wallet: widget.wallet,
          nostrService: widget.nostrService,
        ),
      ),
    );
  }

  // ── Following filter ──────────────────────────────────────────────────────

  List<MediaPost> get _followingPosts {
    final filtered = visibleFollowingPosts(
      _posts,
      selfPubkey: widget.wallet.publicKeyHex,
      followedPubkeys: FollowService.instance.following.toSet(),
      followedTags: FollowService.instance.followedTags.toSet(),
    );
    debugPrint('[FeedScreen] Following filter: ${_posts.length} total → ${filtered.length} visible');
    debugPrint('[FeedScreen] selfPubkey: ${widget.wallet.publicKeyHex}');
    debugPrint('[FeedScreen] followedTags: ${FollowService.instance.followedTags}');
    return filtered;
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _buildTabBar(),
        Expanded(
          child: TabBarView(
            controller: _tabController,
            children: [
              _LatestTab(
                posts: _posts,
                allPosts: _posts,
                isLoading: _isLoading,
                error: _error,
                isFetchingMore: _isFetchingMore,
                loadingMediaPostIds: _loadingMediaPostIds,
                onRefresh: _refresh,
                onLoadMore: _loadMorePosts,
                onReport: _reportPost,
                onLike: _toggleLike,
                onMediaUpdated: _hydrateMediaPost,
                onAvatarTap: _openUserProfile,
                wallet: widget.wallet,
                nostrService: widget.nostrService,
                eventRepo: _repo,
              ),
              _FollowingTab(
                posts: _followingPosts,
                allPosts: _posts,
                isLoading: _isLoading,
                loadingMediaPostIds: _loadingMediaPostIds,
                onRefresh: _refresh,
                onReport: _reportPost,
                onLike: _toggleLike,
                onMediaUpdated: _hydrateMediaPost,
                onAvatarTap: _openUserProfile,
                wallet: widget.wallet,
                nostrService: widget.nostrService,
                eventRepo: _repo,
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildTabBar() {
    return TabBar(
      controller: _tabController,
      labelColor: SpotColors.accent,
      unselectedLabelColor: SpotColors.textTertiary,
      indicatorColor: SpotColors.accent,
      indicatorWeight: 1.5,
      dividerColor: Colors.transparent,
      labelStyle: SpotType.caption.copyWith(letterSpacing: 0.8, fontSize: 11),
      tabs: const [
        Tab(text: 'LATEST'),
        Tab(text: 'FOLLOWING'),
      ],
    );
  }
}

// ── Latest tab ────────────────────────────────────────────────────────────────

class _LatestTab extends StatefulWidget {
  const _LatestTab({
    required this.posts,
    required this.allPosts,
    required this.isLoading,
    required this.isFetchingMore,
    required this.loadingMediaPostIds,
    this.error,
    required this.onRefresh,
    required this.onLoadMore,
    required this.onReport,
    required this.onLike,
    required this.onMediaUpdated,
    required this.onAvatarTap,
    required this.wallet,
    required this.nostrService,
    required this.eventRepo,
  });

  final List<MediaPost> posts;
  final List<MediaPost> allPosts;
  final bool isLoading;
  final bool isFetchingMore;
  final Set<String> loadingMediaPostIds;
  final String? error;
  final Future<void> Function() onRefresh;
  final Future<void> Function() onLoadMore;
  final void Function(MediaPost) onReport;
  final void Function(MediaPost) onLike;
  final void Function(MediaPost) onMediaUpdated;
  final void Function(BuildContext, String) onAvatarTap;
  final WalletModel wallet;
  final NostrService nostrService;
  final EventRepository eventRepo;

  @override
  State<_LatestTab> createState() => _LatestTabState();
}

class _LatestTabState extends State<_LatestTab> {
  final _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent - 200) {
      widget.onLoadMore();
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.isLoading && widget.posts.isEmpty) {
      return _buildLoading();
    }
    if (widget.error != null && widget.posts.isEmpty) {
      return _buildError(context);
    }
    if (widget.posts.isEmpty) {
      return _buildEmpty();
    }

    return RefreshIndicator(
      color: SpotColors.accent,
      backgroundColor: SpotColors.surface,
      displacement: 28,
      onRefresh: widget.onRefresh,
      child: Builder(
        builder: (ctx) {
          final roots = topLevelThreadPosts(widget.posts);
          return ListView.builder(
            controller: _scrollController,
            padding: const EdgeInsets.only(
              top: SpotSpacing.sm,
              bottom: SpotSpacing.xl,
            ),
            itemCount: roots.length + 1,
            itemBuilder: (ctx, i) {
              if (i == roots.length) {
                return widget.isFetchingMore
                    ? const Padding(
                        padding: EdgeInsets.all(SpotSpacing.xl),
                        child: Center(
                          child: SizedBox(
                            width: 120,
                            child: LinearProgressIndicator(
                              minHeight: 2,
                              color: SpotColors.textTertiary,
                              backgroundColor: SpotColors.surfaceHigh,
                            ),
                          ),
                        ),
                      )
                    : const SizedBox(height: SpotSpacing.lg);
              }
              final post = roots[i];
              return InkWell(
                onTap: () => Navigator.of(ctx).push(
                  buildThreadScreenRoute(
                    rootPostId: post.nostrEventId,
                    initialPosts: widget.allPosts,
                    wallet: widget.wallet,
                    nostrService: widget.nostrService,
                    eventRepo: widget.eventRepo,
                  ),
                ),
                child: PostThreadRow(
                  post: post,
                  isLast: true,
                  isMediaLoading: widget.loadingMediaPostIds.contains(post.id),
                  onAvatarTap: () => widget.onAvatarTap(ctx, post.pubkey),
                  onReport: () => widget.onReport(post),
                  onLike: () => widget.onLike(post),
                  onMediaUpdated: widget.onMediaUpdated,
                  onReply: () => showPostComposer(
                    ctx,
                    wallet: widget.wallet,
                    nostrService: widget.nostrService,
                    eventRepo: widget.eventRepo,
                    replyToPost: post,
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }

  Widget _buildLoading() => Center(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Image.asset(
          'assets/logo_transparent.png',
          height: 40,
          fit: BoxFit.contain,
        ),
        const SizedBox(height: SpotSpacing.xl),
        const SizedBox(
          width: 120,
          child: LinearProgressIndicator(
            minHeight: 2,
            color: SpotColors.accent,
            backgroundColor: SpotColors.surfaceHigh,
          ),
        ),
      ],
    ),
  );

  Widget _buildError(BuildContext context) => RefreshIndicator(
    onRefresh: widget.onRefresh,
    color: SpotColors.accent,
    backgroundColor: SpotColors.surface,
    displacement: 28,
    child: CustomScrollView(
      physics: const AlwaysScrollableScrollPhysics(),
      slivers: [
        SliverFillRemaining(
          hasScrollBody: false,
          child: Center(
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
                  const Text(
                    'Could not connect to relays',
                    style: SpotType.bodySecondary,
                  ),
                  const SizedBox(height: SpotSpacing.xl),
                  GestureDetector(
                    onTap: widget.onRefresh,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: SpotSpacing.xl,
                        vertical: SpotSpacing.sm,
                      ),
                      decoration: BoxDecoration(
                        border: Border.all(
                          color: SpotColors.border,
                          width: 0.5,
                        ),
                        borderRadius: BorderRadius.circular(SpotRadius.sm),
                      ),
                      child: const Text('Retry', style: SpotType.bodySecondary),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    ),
  );

  Widget _buildEmpty() => RefreshIndicator(
    onRefresh: widget.onRefresh,
    color: SpotColors.accent,
    backgroundColor: SpotColors.surface,
    displacement: 28,
    child: CustomScrollView(
      physics: const AlwaysScrollableScrollPhysics(),
      slivers: [
        SliverFillRemaining(
          hasScrollBody: false,
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  CupertinoIcons.tray,
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
                const Text('Be the first to record', style: SpotType.caption),
              ],
            ),
          ),
        ),
      ],
    ),
  );
}

// ── Following tab ─────────────────────────────────────────────────────────────

class _FollowingTab extends StatelessWidget {
  const _FollowingTab({
    required this.posts,
    required this.allPosts,
    required this.isLoading,
    required this.loadingMediaPostIds,
    required this.onRefresh,
    required this.onReport,
    required this.onLike,
    required this.onMediaUpdated,
    required this.onAvatarTap,
    required this.wallet,
    required this.nostrService,
    required this.eventRepo,
  });

  final List<MediaPost> posts;
  final List<MediaPost> allPosts;
  final bool isLoading;
  final Set<String> loadingMediaPostIds;
  final Future<void> Function() onRefresh;
  final void Function(MediaPost) onReport;
  final void Function(MediaPost) onLike;
  final void Function(MediaPost) onMediaUpdated;
  final void Function(BuildContext, String) onAvatarTap;
  final WalletModel wallet;
  final NostrService nostrService;
  final EventRepository eventRepo;

  @override
  Widget build(BuildContext context) {
    if (isLoading && posts.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Image.asset(
              'assets/logo_transparent.png',
              height: 40,
              fit: BoxFit.contain,
            ),
            const SizedBox(height: SpotSpacing.xl),
            const SizedBox(
              width: 120,
              child: LinearProgressIndicator(
                minHeight: 2,
                color: SpotColors.accent,
                backgroundColor: SpotColors.surfaceHigh,
              ),
            ),
          ],
        ),
      );
    }
    if (posts.isEmpty) {
      return RefreshIndicator(
        onRefresh: onRefresh,
        color: SpotColors.accent,
        backgroundColor: SpotColors.surface,
        displacement: 28,
        child: CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            const SliverFillRemaining(
              hasScrollBody: false,
              child: Center(
                child: Padding(
                  padding: EdgeInsets.all(SpotSpacing.xxxl),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        CupertinoIcons.person_2,
                        color: SpotColors.overlay,
                        size: 36,
                      ),
                      SizedBox(height: SpotSpacing.lg),
                      Text(
                        'No posts from people you follow',
                        style: SpotType.bodySecondary,
                        textAlign: TextAlign.center,
                      ),
                      SizedBox(height: SpotSpacing.xs),
                      Text(
                        'Tap an avatar to follow someone',
                        style: SpotType.caption,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      color: SpotColors.accent,
      backgroundColor: SpotColors.surface,
      displacement: 28,
      onRefresh: onRefresh,
      child: Builder(
        builder: (ctx) {
          final roots = topLevelThreadPosts(posts);
          return ListView.builder(
            padding: const EdgeInsets.only(
              top: SpotSpacing.sm,
              bottom: SpotSpacing.xl,
            ),
            itemCount: roots.length,
            itemBuilder: (ctx, i) {
              final post = roots[i];
              return InkWell(
                onTap: () => Navigator.of(ctx).push(
                  buildThreadScreenRoute(
                    rootPostId: post.nostrEventId,
                    initialPosts: allPosts,
                    wallet: wallet,
                    nostrService: nostrService,
                    eventRepo: eventRepo,
                  ),
                ),
                child: PostThreadRow(
                  post: post,
                  isLast: true,
                  isMediaLoading: loadingMediaPostIds.contains(post.id),
                  onAvatarTap: () => onAvatarTap(ctx, post.pubkey),
                  onReport: () => onReport(post),
                  onLike: () => onLike(post),
                  onMediaUpdated: onMediaUpdated,
                  onReply: () => showPostComposer(
                    ctx,
                    wallet: wallet,
                    nostrService: nostrService,
                    eventRepo: eventRepo,
                    replyToPost: post,
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}
