import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import 'package:mobile/core/tag_normalizer.dart';
import 'package:mobile/features/event/event_repository.dart';
import 'package:mobile/features/metadata/metadata_service.dart';
import 'package:mobile/features/p2p/p2p_service.dart';
import 'package:mobile/models/event_model.dart';
import 'package:mobile/models/media_post.dart';
import 'package:mobile/models/wallet_model.dart';
import 'package:mobile/screens/post_composer_screen.dart';
import 'package:mobile/screens/thread_screen.dart';
import 'package:mobile/screens/user_profile_screen.dart';
import 'package:mobile/services/discover_feed_service.dart';
import 'package:mobile/services/feed_scoring_service.dart';
import 'package:mobile/services/follow_service.dart';
import 'package:mobile/services/location_service.dart';
import 'package:mobile/services/local_post_store.dart';
import 'package:mobile/services/media_resolver.dart';
import 'package:mobile/services/media_sync_service.dart';
import 'package:mobile/services/post_merge.dart';
import 'package:mobile/services/post_thread_ordering.dart';
import 'package:mobile/services/user_prefs_service.dart';
import 'package:mobile/theme/spot_theme.dart';
import 'package:mobile/widgets/post_thread_row.dart';

/// Discover screen — TRENDING / FOR YOU / NEARBY.
///
/// Shows algorithmically ranked and geo-filtered content.
/// Moving discovery tabs here keeps the home feed focused on chronology.
String normalizeDiscoverSearchQuery(String query) => query.trim().toLowerCase();

String? discoverFollowableTagForQuery(String query) {
  final normalizedQuery = normalizeDiscoverSearchQuery(query);
  if (!normalizedQuery.startsWith('#')) return null;
  final tag = normalizeTag(normalizedQuery.substring(1));
  if (tag.isEmpty) return null;
  return tag;
}

Route<void> buildDiscoverScreenRoute({
  required WalletModel wallet,
  String initialSearchQuery = '',
}) {
  return CupertinoPageRoute<void>(
    builder: (_) => Scaffold(
      backgroundColor: SpotColors.bg,
      body: DiscoverScreen(
        wallet: wallet,
        initialSearchQuery: initialSearchQuery,
        showBackButton: true,
      ),
    ),
  );
}

bool discoverThreadPostMatchesQuery(MediaPost post, String query) {
  final normalizedQuery = normalizeDiscoverSearchQuery(query);
  if (normalizedQuery.isEmpty) return true;

  final isTagQuery = normalizedQuery.startsWith('#');
  final effectiveQuery = isTagQuery
      ? normalizedQuery.substring(1).trim()
      : normalizedQuery;
  if (effectiveQuery.isEmpty) return true;

  final normalizedTags = [
    ...post.eventTags.map((tag) => tag.toLowerCase()),
    ...post.tags.map((tag) => tag.toLowerCase()),
  ];
  final tagMatches = normalizedTags.any((tag) => tag.contains(effectiveQuery));
  if (isTagQuery) return tagMatches;

  final searchableText = [
    post.caption,
    post.spotName,
    ...post.eventTags,
    ...post.tags,
  ].whereType<String>().join(' ').toLowerCase();
  return tagMatches || searchableText.contains(effectiveQuery);
}

List<MediaPost> visibleDiscoverThreads(
  Iterable<MediaPost> posts, {
  String query = '',
}) {
  final roots = topLevelThreadPosts(posts);
  final normalizedQuery = normalizeDiscoverSearchQuery(query);
  if (normalizedQuery.isEmpty) return roots;

  final entriesByRoot = <String, List<ThreadedPostEntry>>{};
  for (final entry in buildThreadedPostEntries(posts)) {
    entriesByRoot
        .putIfAbsent(entry.rootId, () => <ThreadedPostEntry>[])
        .add(entry);
  }

  return roots
      .where((root) {
        final threadEntries = entriesByRoot[root.nostrEventId] ?? const [];
        return threadEntries.any(
          (entry) =>
              discoverThreadPostMatchesQuery(entry.post, normalizedQuery),
        );
      })
      .toList(growable: false);
}

class DiscoverScreen extends StatefulWidget {
  const DiscoverScreen({
    super.key,
    required this.wallet,
    this.initialSearchQuery = '',
    this.showBackButton = false,
  });

  final WalletModel wallet;
  final String initialSearchQuery;
  final bool showBackButton;

  @override
  State<DiscoverScreen> createState() => _DiscoverScreenState();
}

class _DiscoverScreenState extends State<DiscoverScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;
  late final EventRepository _repo;
  StreamSubscription<CivicEvent>? _sub;
  StreamSubscription<void>? _followChangesSub;
  final TextEditingController _searchController = TextEditingController();

  List<MediaPost> _posts = [];
  bool _isLoading = true;
  final Set<String> _loadingMediaPostIds = {};
  String _searchQuery = '';
  bool _isFollowingSearchTag = false;

  double? _userLat;
  double? _userLon;

  final _scoring = const FeedScoringService();

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _tabController.addListener(_onTabChanged);
    _repo = EventRepository();
    _searchQuery = widget.initialSearchQuery;
    _searchController.text = widget.initialSearchQuery;
    _initFeed();
    _loadLocation();
    unawaited(_initFollowState());
  }

  @override
  void dispose() {
    _tabController.removeListener(_onTabChanged);
    _tabController.dispose();
    _sub?.cancel();
    _followChangesSub?.cancel();
    _repo.dispose();
    _searchController.dispose();
    super.dispose();
  }

  void _onTabChanged() {
    if (_tabController.indexIsChanging) return;
    if (_tabController.index == 2 && _userLat == null) {
      _loadLocation();
    }
  }

  Future<void> _initFollowState() async {
    await FollowService.instance.init();
    if (!mounted) return;
    _followChangesSub = FollowService.instance.changes.listen((_) {
      if (!mounted) return;
      setState(() {
        _isFollowingSearchTag =
            _currentSearchTag != null &&
            FollowService.instance.isFollowingTag(_currentSearchTag!);
      });
    });
    setState(() {
      _isFollowingSearchTag =
          _currentSearchTag != null &&
          FollowService.instance.isFollowingTag(_currentSearchTag!);
    });
  }

  String? get _currentSearchTag => discoverFollowableTagForQuery(_searchQuery);

  void _onSearchChanged(String value) {
    setState(() {
      _searchQuery = value;
      _isFollowingSearchTag =
          _currentSearchTag != null &&
          FollowService.instance.isFollowingTag(_currentSearchTag!);
    });
  }

  Future<void> _toggleFollowSearchTag() async {
    final tag = _currentSearchTag;
    if (tag == null) return;
    if (_isFollowingSearchTag) {
      await FollowService.instance.unfollowTag(tag);
    } else {
      await FollowService.instance.followTag(tag);
    }
    if (!mounted) return;
    setState(() => _isFollowingSearchTag = !_isFollowingSearchTag);
  }

  void _openDiscoverTag(String tag) {
    Navigator.of(context).push(
      buildDiscoverScreenRoute(
        wallet: widget.wallet,
        initialSearchQuery: '#$tag',
      ),
    );
  }

  // ── Data loading ──────────────────────────────────────────────────────────

  Future<void> _initFeed() async {
    setState(() {
      _isLoading = true;
    });
    try {
      await _loadPersistedPosts();
      _sub = _repo.subscribeToEvents().listen(_onEvent);
    } catch (_) {
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _onEvent(CivicEvent event) {
    if (!mounted) return;
    final merged = _mergePosts(_posts, event.posts);
    if (orderedPostsEqual(merged, _posts)) return;
    unawaited(LocalPostStore.instance.savePosts(event.posts));
    setState(() => _posts = merged);
  }

  Future<void> _refresh() async {
    await _sub?.cancel();
    _repo.reset();
    setState(() => _posts = []);
    await _initFeed();
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

  Future<void> _loadPersistedPosts() async {
    final persisted = await LocalPostStore.instance.loadPosts();
    if (!mounted || persisted.isEmpty) return;
    setState(() => _posts = _mergePosts(_posts, persisted));
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

  // ── Post actions ──────────────────────────────────────────────────────────

  Future<void> _reportPost(MediaPost post) async {
    try {
      await MetadataService.instance.reportContent(
        postId: post.nostrEventId,
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

  void _openUserProfile(BuildContext ctx, String pubkey) {
    if (pubkey == widget.wallet.publicKeyHex) return;
    Navigator.of(ctx).push(
      MaterialPageRoute(
        builder: (_) =>
            UserProfileScreen(pubkey: pubkey, wallet: widget.wallet),
      ),
    );
  }

  // ── Scoring ───────────────────────────────────────────────────────────────

  List<MediaPost> get _trendingPosts {
    return visibleTrendingPosts(
      localPosts: _posts,
      events: _repo.getAllEvents(),
      scoring: _scoring,
    );
  }

  List<MediaPost> get _forYouPosts {
    final interests = UserPrefsService.instance.interests;
    final viewed = UserPrefsService.instance.viewedHashtags;
    return List<MediaPost>.from(_posts)..sort((a, b) {
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

  List<MediaPost> get _nearbyPosts {
    if (_userLat == null || _userLon == null) return [];
    return List<MediaPost>.from(_posts.where((p) => p.hasGps))..sort((a, b) {
      final sa = _scoring.nearbyScore(a, _userLat!, _userLon!);
      final sb = _scoring.nearbyScore(b, _userLat!, _userLon!);
      return sb.compareTo(sa);
    });
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      bottom: false,
      child: Column(
        children: [
          _buildHeader(),
          _buildTabBar(),
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                _buildScoredList(
                  posts: _trendingPosts,
                  emptyLabel: 'Nothing trending in the last 48 h',
                ),
                _buildScoredList(
                  posts: _forYouPosts,
                  emptyLabel: UserPrefsService.instance.hasSetInterests
                      ? 'No recommended posts yet'
                      : 'Set your interests to see personalised content',
                ),
                _buildNearbyList(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    final currentSearchTag = _currentSearchTag;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        SpotSpacing.lg,
        SpotSpacing.sm,
        SpotSpacing.lg,
        SpotSpacing.sm,
      ),
      child: Column(
        children: [
          Row(
            children: [
              if (widget.showBackButton) ...[
                IconButton(
                  onPressed: () => Navigator.of(context).maybePop(),
                  icon: const Icon(CupertinoIcons.back, size: 20),
                  color: SpotColors.textSecondary,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints.tightFor(
                    width: 28,
                    height: 28,
                  ),
                ),
                const SizedBox(width: SpotSpacing.sm),
              ],
              const Text('Discover', style: SpotType.subheading),
              const SizedBox(width: SpotSpacing.md),
              Expanded(
                child: CupertinoSearchTextField(
                  controller: _searchController,
                  placeholder: 'Search threads or #tags',
                  backgroundColor: SpotColors.surface,
                  itemColor: SpotColors.textSecondary,
                  style: SpotType.body.copyWith(color: SpotColors.textPrimary),
                  onChanged: _onSearchChanged,
                ),
              ),
            ],
          ),
          if (currentSearchTag != null) ...[
            const SizedBox(height: SpotSpacing.xs),
            Row(
              children: [
                Text('#$currentSearchTag', style: SpotType.caption),
                const Spacer(),
                TextButton.icon(
                  onPressed: _toggleFollowSearchTag,
                  icon: Icon(
                    _isFollowingSearchTag
                        ? CupertinoIcons.star_fill
                        : CupertinoIcons.add,
                    size: 16,
                  ),
                  label: Text(
                    _isFollowingSearchTag
                        ? 'Remove Favorite'
                        : 'Add as Favorite',
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
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
        Tab(text: 'TRENDING'),
        Tab(text: 'FOR YOU'),
        Tab(text: 'NEARBY'),
      ],
    );
  }

  Widget _buildScoredList({
    required List<MediaPost> posts,
    required String emptyLabel,
  }) {
    final roots = visibleDiscoverThreads(posts, query: _searchQuery);
    if (_isLoading && roots.isEmpty) {
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
              width: 16,
              height: 16,
              child: CircularProgressIndicator(
                color: SpotColors.accent,
                strokeWidth: 1,
              ),
            ),
          ],
        ),
      );
    }
    if (roots.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(SpotSpacing.xxxl),
          child: Text(
            normalizeDiscoverSearchQuery(_searchQuery).isNotEmpty
                ? 'No threads found for "${_searchQuery.trim()}"'
                : emptyLabel,
            style: SpotType.bodySecondary,
            textAlign: TextAlign.center,
          ),
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
            itemCount: roots.length,
            itemBuilder: (ctx, i) {
              final post = roots[i];
              return InkWell(
                onTap: () => Navigator.of(ctx).push(
                  buildThreadScreenRoute(
                    rootPostId: post.nostrEventId,
                    initialPosts: _posts,
                    wallet: widget.wallet,
                    eventRepo: _repo,
                  ),
                ),
                child: PostThreadRow(
                  post: post,
                  isLast: true,
                  isMediaLoading: _loadingMediaPostIds.contains(post.id),
                  onAvatarTap: () => _openUserProfile(ctx, post.pubkey),
                  onTagTap: _openDiscoverTag,
                  onReport: () => _reportPost(post),
                  onLike: () => _toggleLike(post),
                  onMediaUpdated: _hydrateMediaPost,
                  onReply: () => showPostComposer(
                    ctx,
                    wallet: widget.wallet,
                    eventRepo: _repo,
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

  Widget _buildNearbyList() {
    if (!(_userLat != null)) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(SpotSpacing.xxxl),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                CupertinoIcons.location_slash,
                color: SpotColors.textTertiary,
                size: 32,
              ),
              const SizedBox(height: SpotSpacing.xl),
              const Text(
                'Enable location to see nearby events',
                style: SpotType.bodySecondary,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: SpotSpacing.xl),
              GestureDetector(
                onTap: _loadLocation,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: SpotSpacing.xl,
                    vertical: SpotSpacing.sm,
                  ),
                  decoration: BoxDecoration(
                    border: Border.all(color: SpotColors.border, width: 0.5),
                    borderRadius: BorderRadius.circular(SpotRadius.sm),
                  ),
                  child: const Text(
                    'Allow Location',
                    style: SpotType.bodySecondary,
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }

    return _buildScoredList(
      posts: _nearbyPosts,
      emptyLabel: 'No events near you',
    );
  }
}
