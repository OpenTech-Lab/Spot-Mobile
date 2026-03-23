import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import 'package:mobile/features/camera/camera_screen.dart';
import 'package:mobile/features/event/event_repository.dart';
import 'package:mobile/features/nostr/nostr_models.dart';
import 'package:mobile/features/nostr/nostr_service.dart';
import 'package:mobile/models/event_model.dart';
import 'package:mobile/models/media_post.dart';
import 'package:mobile/models/wallet_model.dart';
import 'package:mobile/screens/interests_screen.dart';
import 'package:mobile/services/cache_manager.dart';
import 'package:mobile/services/feed_scoring_service.dart';
import 'package:mobile/services/local_post_store.dart';
import 'package:mobile/services/location_service.dart';
import 'package:mobile/services/user_prefs_service.dart';
import 'package:mobile/theme/spot_theme.dart';
import 'package:mobile/widgets/post_thread_row.dart';

/// Four-tab discovery feed (v1.5 Feed Discovery Upgrade).
///
/// Tabs:
/// - **Latest** – reverse-chronological, real-time, infinite scroll
/// - **For You** – Scheme B client-side recommendation (hashtag + GPS + freshness)
/// - **Trending** – Scheme A local scoring over last 48 h
/// - **Nearby** – GPS-proximity filtered
class FeedScreen extends StatefulWidget {
  const FeedScreen({
    super.key,
    required this.nostrService,
    required this.wallet,
  });

  final NostrService nostrService;
  final WalletModel wallet;

  @override
  State<FeedScreen> createState() => _FeedScreenState();
}

class _FeedScreenState extends State<FeedScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;
  late final EventRepository _repo;
  StreamSubscription<CivicEvent>? _sub;

  List<MediaPost> _posts = [];
  bool _isLoading = true;
  String? _error;

  // Infinite scroll state (Latest tab)
  bool _isFetchingMore = false;
  int? _oldestTimestamp; // unix seconds

  final _scoring = const FeedScoringService();

  // Current device location (Nearby + For You)
  double? _userLat;
  double? _userLon;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
    _tabController.addListener(_onTabChanged);
    _repo = EventRepository(nostrService: widget.nostrService);
    _initFeed();
    _loadLocation();
    _showInterestsIfNeeded();
  }

  @override
  void dispose() {
    _tabController.removeListener(_onTabChanged);
    _tabController.dispose();
    _sub?.cancel();
    _repo.dispose();
    super.dispose();
  }

  void _onTabChanged() {
    if (_tabController.indexIsChanging) return;
    // Record that Nearby was opened → load location if not yet available
    if (_tabController.index == 3 && _userLat == null) {
      _loadLocation();
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
    final merged = _mergePosts(_posts, event.posts);
    if (merged.length == _posts.length) return;
    setState(() => _posts = merged);
  }

  Future<void> _refresh() async {
    await _sub?.cancel();
    _repo.reset();
    _oldestTimestamp = null;
    setState(() => _posts = []);
    await _initFeed();
  }

  Future<void> _loadPersistedPosts() async {
    final persisted = await LocalPostStore.instance.loadPosts(
      authorPubkey: widget.wallet.publicKeyHex,
    );
    final visible = persisted
        .where(
          (post) => post.contentHashes
              .every((hash) => !CacheManager.instance.isBlocked(hash)),
        )
        .toList();
    if (!mounted || visible.isEmpty) return;
    setState(() => _posts = _mergePosts(_posts, visible));
  }

  /// Fetches older posts via a Nostr REQ with `until: [timestamp]`.
  Future<void> _loadMorePosts() async {
    if (_isFetchingMore) return;
    if (_posts.isEmpty) return;

    final cursor = _oldestTimestamp ??
        (_posts.last.capturedAt.millisecondsSinceEpoch ~/ 1000) - 1;

    setState(() => _isFetchingMore = true);

    try {
      final completer = Completer<void>();
      Timer? timeout;

      final subId = widget.nostrService.subscribe(
        [
          NostrFilter(
            kinds: [1],
            limit: 20,
            until: cursor,
            tags: {'app': ['spot']},
          ),
        ],
        (event) {
          _repo.addPost(
            EventRepository.nostrEventToPost(event, event.getTagValue('t')),
          );
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
        final allPosts = _repo
            .getAllEvents()
            .expand((e) => e.posts)
            .toList()
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

  Future<void> _loadLocation() async {
    final pos = await LocationService.instance.getCurrentPosition();
    if (pos != null && mounted) {
      setState(() {
        _userLat = pos.latitude;
        _userLon = pos.longitude;
      });
    }
  }

  Future<void> _showInterestsIfNeeded() async {
    await UserPrefsService.instance.init();
    if (UserPrefsService.instance.hasSetInterests) return;
    if (!mounted) return;
    // Small delay so the feed is visible first
    await Future<void>.delayed(const Duration(milliseconds: 600));
    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => InterestsScreen(
        onDone: () => setState(() {}),
      ),
    );
  }

  // ── Post helpers ──────────────────────────────────────────────────────────

  List<MediaPost> _mergePosts(
    List<MediaPost> current,
    Iterable<MediaPost> incoming,
  ) {
    final byId = {for (final post in current) post.id: post};
    for (final post in incoming) {
      if (!CacheManager.instance.isBlocked(post.contentHash)) {
        byId[post.id] = post;
      }
    }
    return byId.values.toList()
      ..sort((a, b) => b.capturedAt.compareTo(a.capturedAt));
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

  // ── Scoring ───────────────────────────────────────────────────────────────

  List<MediaPost> get _forYouPosts {
    final interests = UserPrefsService.instance.interests;
    final viewed = UserPrefsService.instance.viewedHashtags;
    return List<MediaPost>.from(_posts)
      ..sort((a, b) {
        final sa = _scoring.recommendationScore(
          post: a,
          userInterests: interests,
          viewedHashtags: viewed,
          userLat: _userLat,
          userLon: _userLon,
        );
        final sb = _scoring.recommendationScore(
          post: b,
          userInterests: interests,
          viewedHashtags: viewed,
          userLat: _userLat,
          userLon: _userLon,
        );
        return sb.compareTo(sa);
      });
  }

  List<MediaPost> get _trendingPosts {
    // Group by eventTag, compute per-event trending score, then flatten posts
    final events = _repo.getAllEvents();
    final scored = events
        .where((e) => DateTime.now().difference(e.firstSeen).inHours <= 48)
        .toList()
      ..sort((a, b) =>
          _scoring.trendingScore(b).compareTo(_scoring.trendingScore(a)));

    final result = <MediaPost>[];
    for (final event in scored) {
      result.addAll(event.postsByNewest);
    }
    // Also include untagged posts sorted by recency
    final untagged =
        _posts.where((p) => p.eventTag == null || p.eventTag == '_unsorted');
    result.addAll(untagged);

    // Deduplicate
    final seen = <String>{};
    return result.where((p) => seen.add(p.id)).toList();
  }

  List<MediaPost> get _nearbyPosts {
    if (_userLat == null || _userLon == null) return [];
    return List<MediaPost>.from(_posts.where((p) => p.hasGps))
      ..sort((a, b) {
        final sa = _scoring.nearbyScore(a, _userLat!, _userLon!);
        final sb = _scoring.nearbyScore(b, _userLat!, _userLon!);
        return sb.compareTo(sa);
      });
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
                isLoading: _isLoading,
                error: _error,
                isFetchingMore: _isFetchingMore,
                onRefresh: _refresh,
                onLoadMore: _loadMorePosts,
                onReport: _reportPost,
                wallet: widget.wallet,
                nostrService: widget.nostrService,
              ),
              _ScoredTab(
                posts: _forYouPosts,
                isLoading: _isLoading,
                emptyLabel: UserPrefsService.instance.hasSetInterests
                    ? 'No recommended posts yet'
                    : 'Set your interests to see personalised content',
                onRefresh: _refresh,
                onReport: _reportPost,
                wallet: widget.wallet,
                nostrService: widget.nostrService,
              ),
              _ScoredTab(
                posts: _trendingPosts,
                isLoading: _isLoading,
                emptyLabel: 'Nothing trending in the last 48 h',
                onRefresh: _refresh,
                onReport: _reportPost,
                wallet: widget.wallet,
                nostrService: widget.nostrService,
              ),
              _NearbyTab(
                posts: _nearbyPosts,
                isLoading: _isLoading,
                hasLocation: _userLat != null,
                onRefresh: _refresh,
                onReport: _reportPost,
                wallet: widget.wallet,
                nostrService: widget.nostrService,
                onRequestLocation: _loadLocation,
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
      labelStyle:
          SpotType.caption.copyWith(letterSpacing: 0.8, fontSize: 11),
      tabs: const [
        Tab(text: 'LATEST'),
        Tab(text: 'FOR YOU'),
        Tab(text: 'TRENDING'),
        Tab(text: 'NEARBY'),
      ],
    );
  }
}

// ── Latest tab ────────────────────────────────────────────────────────────────

/// Reverse-chronological feed with real-time updates and infinite scroll.
class _LatestTab extends StatefulWidget {
  const _LatestTab({
    required this.posts,
    required this.isLoading,
    required this.isFetchingMore,
    this.error,
    required this.onRefresh,
    required this.onLoadMore,
    required this.onReport,
    required this.wallet,
    required this.nostrService,
  });

  final List<MediaPost> posts;
  final bool isLoading;
  final bool isFetchingMore;
  final String? error;
  final Future<void> Function() onRefresh;
  final Future<void> Function() onLoadMore;
  final void Function(MediaPost) onReport;
  final WalletModel wallet;
  final NostrService nostrService;

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
      child: ListView.builder(
        controller: _scrollController,
        padding: const EdgeInsets.only(
          top: SpotSpacing.sm,
          bottom: SpotSpacing.xl,
        ),
        itemCount: widget.posts.length + 1,
        itemBuilder: (ctx, i) {
          if (i == widget.posts.length) {
            return widget.isFetchingMore
                ? const Padding(
                    padding: EdgeInsets.all(SpotSpacing.xl),
                    child: Center(
                      child: SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 1,
                          color: SpotColors.textTertiary,
                        ),
                      ),
                    ),
                  )
                : const SizedBox(height: SpotSpacing.lg);
          }
          final post = widget.posts[i];
          return PostThreadRow(
            post: post,
            isLast: i == widget.posts.length - 1,
            onReport: () => widget.onReport(post),
            onReply: () => Navigator.of(ctx).push(
              MaterialPageRoute(
                builder: (_) => CameraScreen(
                  wallet: widget.wallet,
                  nostrService: widget.nostrService,
                  replyToPost: post,
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildLoading() => const Center(
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
            Text('Connecting', style: SpotType.label),
          ],
        ),
      );

  Widget _buildError(BuildContext context) => Center(
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
                    border:
                        Border.all(color: SpotColors.border, width: 0.5),
                    borderRadius: BorderRadius.circular(SpotRadius.sm),
                  ),
                  child: const Text('Retry', style: SpotType.bodySecondary),
                ),
              ),
            ],
          ),
        ),
      );

  Widget _buildEmpty() => Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(CupertinoIcons.tray,
                color: SpotColors.overlay, size: 36),
            const SizedBox(height: SpotSpacing.lg),
            Text(
              'No posts yet',
              style:
                  SpotType.bodySecondary.copyWith(fontWeight: FontWeight.w300),
            ),
            const SizedBox(height: SpotSpacing.xs),
            const Text('Be the first to record', style: SpotType.caption),
          ],
        ),
      );
}

// ── Scored tab (For You / Trending) ───────────────────────────────────────────

/// Generic tab that displays a pre-scored [posts] list.
class _ScoredTab extends StatelessWidget {
  const _ScoredTab({
    required this.posts,
    required this.isLoading,
    required this.emptyLabel,
    required this.onRefresh,
    required this.onReport,
    required this.wallet,
    required this.nostrService,
  });

  final List<MediaPost> posts;
  final bool isLoading;
  final String emptyLabel;
  final Future<void> Function() onRefresh;
  final void Function(MediaPost) onReport;
  final WalletModel wallet;
  final NostrService nostrService;

  @override
  Widget build(BuildContext context) {
    if (isLoading && posts.isEmpty) {
      return const Center(
        child: SizedBox(
          width: 18,
          height: 18,
          child: CircularProgressIndicator(
              color: SpotColors.accent, strokeWidth: 1),
        ),
      );
    }
    if (posts.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(SpotSpacing.xxxl),
          child: Text(emptyLabel, style: SpotType.bodySecondary,
              textAlign: TextAlign.center),
        ),
      );
    }

    return RefreshIndicator(
      color: SpotColors.accent,
      backgroundColor: SpotColors.surface,
      displacement: 28,
      onRefresh: onRefresh,
      child: ListView.builder(
        padding: const EdgeInsets.only(
          top: SpotSpacing.sm,
          bottom: SpotSpacing.xl,
        ),
        itemCount: posts.length,
        itemBuilder: (ctx, i) {
          final post = posts[i];
          return PostThreadRow(
            post: post,
            isLast: i == posts.length - 1,
            onReport: () => onReport(post),
            onReply: () => Navigator.of(ctx).push(
              MaterialPageRoute(
                builder: (_) => CameraScreen(
                  wallet: wallet,
                  nostrService: nostrService,
                  replyToPost: post,
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

// ── Nearby tab ────────────────────────────────────────────────────────────────

/// GPS-filtered feed sorted by proximity to the current device location.
class _NearbyTab extends StatelessWidget {
  const _NearbyTab({
    required this.posts,
    required this.isLoading,
    required this.hasLocation,
    required this.onRefresh,
    required this.onReport,
    required this.wallet,
    required this.nostrService,
    required this.onRequestLocation,
  });

  final List<MediaPost> posts;
  final bool isLoading;
  final bool hasLocation;
  final Future<void> Function() onRefresh;
  final void Function(MediaPost) onReport;
  final WalletModel wallet;
  final NostrService nostrService;
  final Future<void> Function() onRequestLocation;

  @override
  Widget build(BuildContext context) {
    if (!hasLocation) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(SpotSpacing.xxxl),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(CupertinoIcons.location_slash,
                  color: SpotColors.textTertiary, size: 32),
              const SizedBox(height: SpotSpacing.xl),
              const Text(
                'Enable location to see nearby events',
                style: SpotType.bodySecondary,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: SpotSpacing.xl),
              GestureDetector(
                onTap: onRequestLocation,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: SpotSpacing.xl,
                    vertical: SpotSpacing.sm,
                  ),
                  decoration: BoxDecoration(
                    border:
                        Border.all(color: SpotColors.border, width: 0.5),
                    borderRadius: BorderRadius.circular(SpotRadius.sm),
                  ),
                  child: const Text('Allow Location',
                      style: SpotType.bodySecondary),
                ),
              ),
            ],
          ),
        ),
      );
    }

    if (isLoading && posts.isEmpty) {
      return const Center(
        child: SizedBox(
          width: 18,
          height: 18,
          child: CircularProgressIndicator(
              color: SpotColors.accent, strokeWidth: 1),
        ),
      );
    }

    if (posts.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(CupertinoIcons.location,
                color: SpotColors.overlay, size: 36),
            const SizedBox(height: SpotSpacing.lg),
            Text(
              'No events near you',
              style:
                  SpotType.bodySecondary.copyWith(fontWeight: FontWeight.w300),
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
      child: ListView.builder(
        padding: const EdgeInsets.only(
          top: SpotSpacing.sm,
          bottom: SpotSpacing.xl,
        ),
        itemCount: posts.length,
        itemBuilder: (ctx, i) {
          final post = posts[i];
          return PostThreadRow(
            post: post,
            isLast: i == posts.length - 1,
            onReport: () => onReport(post),
            onReply: () => Navigator.of(ctx).push(
              MaterialPageRoute(
                builder: (_) => CameraScreen(
                  wallet: wallet,
                  nostrService: nostrService,
                  replyToPost: post,
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
