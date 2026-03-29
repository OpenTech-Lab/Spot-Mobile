import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import 'package:mobile/core/tag_normalizer.dart';
import 'package:mobile/features/event/event_repository.dart';
import 'package:mobile/features/metadata/metadata_service.dart';
import 'package:mobile/features/p2p/p2p_service.dart';
import 'package:mobile/models/event_model.dart';
import 'package:mobile/models/media_post.dart';
import 'package:mobile/models/profile_model.dart';
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
import 'package:mobile/widgets/profile_avatar.dart';
import 'package:mobile/widgets/tabbed_screen_chrome.dart';

/// Discover screen — TRENDING / FOR YOU / NEARBY.
///
/// Shows algorithmically ranked and geo-filtered content.
/// Moving discovery tabs here keeps the home feed focused on chronology.
String normalizeDiscoverSearchQuery(String query) => query.trim().toLowerCase();

enum DiscoverSearchResultMode { keyword, hashtag }

String? discoverSubmittedSearchQuery(String query) {
  final trimmed = query.trim();
  if (trimmed.isEmpty) return null;

  final tag = discoverFollowableTagForQuery(trimmed);
  if (normalizeDiscoverSearchQuery(trimmed).startsWith('#')) {
    return tag == null ? null : '#$tag';
  }

  return trimmed;
}

DiscoverSearchResultMode? discoverSearchResultModeForQuery(String query) {
  final normalizedQuery = normalizeDiscoverSearchQuery(query);
  if (normalizedQuery.isEmpty) return null;
  return normalizedQuery.startsWith('#')
      ? DiscoverSearchResultMode.hashtag
      : DiscoverSearchResultMode.keyword;
}

bool discoverSearchResultUsesTabbedLayout(String query) =>
    discoverSearchResultModeForQuery(query) == DiscoverSearchResultMode.keyword;

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

Route<void> buildDiscoverSearchResultsRoute({
  required WalletModel wallet,
  required String query,
  List<MediaPost> initialPosts = const [],
  Future<List<MediaPost>> Function()? persistedPostsLoader,
  Future<List<ProfileModel>> Function(String query)? profileSearch,
  Stream<CivicEvent> Function()? eventStreamFactory,
}) {
  return CupertinoPageRoute<void>(
    builder: (_) => Scaffold(
      backgroundColor: SpotColors.bg,
      body: DiscoverSearchResultsScreen(
        wallet: wallet,
        initialQuery: query,
        initialPosts: initialPosts,
        persistedPostsLoader: persistedPostsLoader,
        profileSearch: profileSearch,
        eventStreamFactory: eventStreamFactory,
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
  String? excludedAuthorPubkey,
}) {
  final roots = topLevelThreadPosts(posts)
      .where(
        (post) =>
            excludedAuthorPubkey == null || post.pubkey != excludedAuthorPubkey,
      )
      .toList(growable: false);
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

String discoverProfileSearchDisplayName(ProfileModel profile) {
  final displayName = profile.displayName?.trim();
  if (displayName != null && displayName.isNotEmpty) {
    return displayName;
  }
  return 'Citizen';
}

String? discoverProfileSearchSecondaryText(ProfileModel profile) {
  final description = profile.description?.trim();
  if (description != null && description.isNotEmpty) {
    return description;
  }

  final pubkey = profile.legacyPubkey?.trim();
  if (pubkey == null || pubkey.isEmpty) return null;
  if (pubkey.length <= 16) return pubkey;
  return '${pubkey.substring(0, 10)}...${pubkey.substring(pubkey.length - 6)}';
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
  StreamSubscription<List<MediaPost>>? _localSub;
  StreamSubscription<void>? _followChangesSub;
  final TextEditingController _searchController = TextEditingController();

  List<MediaPost> _posts = [];
  bool _isLoading = true;
  final Set<String> _loadingMediaPostIds = {};
  String _searchQuery = '';
  bool _isFollowingSearchTag = false;
  bool _showTopChrome = true;

  double? _userLat;
  double? _userLon;

  final _scoring = const FeedScoringService();

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _tabController.addListener(_onTabChanged);
    _repo = EventRepository();
    _localSub ??= LocalPostStore.instance.changes.listen(_onLocalPostsChanged);
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
    _localSub?.cancel();
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

  void _submitSearch() {
    final query = discoverSubmittedSearchQuery(_searchController.text);
    if (query == null) return;

    Navigator.of(context).push(
      buildDiscoverSearchResultsRoute(
        wallet: widget.wallet,
        query: query,
        initialPosts: _posts,
      ),
    );
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
    final visible = _visiblePersistedPosts(persisted);
    if (!mounted || visible.isEmpty) return;
    setState(() => _posts = _mergePosts(_posts, visible));
  }

  List<MediaPost> _mergePosts(
    List<MediaPost> current,
    Iterable<MediaPost> incoming,
  ) => mergePostsPreservingLocalState(current, incoming);

  List<MediaPost> _visiblePersistedPosts(Iterable<MediaPost> posts) {
    return posts.where((post) => !post.isPendingRetry).toList(growable: false);
  }

  void _onLocalPostsChanged(List<MediaPost> persisted) {
    if (!mounted) return;
    final merged = _mergePosts(_posts, _visiblePersistedPosts(persisted));
    if (orderedPostsEqual(merged, _posts)) return;
    setState(() => _posts = merged);
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

  bool _handleScrollNotification(UserScrollNotification notification) {
    final nextVisibility = tabbedScreenChromeVisibilityForScroll(
      currentVisibility: _showTopChrome,
      direction: notification.direction,
      pixels: notification.metrics.pixels,
      axisDirection: notification.metrics.axisDirection,
    );
    if (nextVisibility != _showTopChrome) {
      setState(() => _showTopChrome = nextVisibility);
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      bottom: false,
      child: Column(
        children: [
          SpotCollapsibleTabbedScreenChrome(
            visible: _showTopChrome,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [_buildHeader(), _buildTabBar()],
            ),
          ),
          Expanded(
            child: NotificationListener<UserScrollNotification>(
              onNotification: _handleScrollNotification,
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
          ),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    final currentSearchTag = _currentSearchTag;
    return Padding(
      padding: spotTabbedScreenHeaderPadding,
      child: Column(
        children: [
          SizedBox(
            height: spotTabbedScreenHeaderRowHeight,
            child: Row(
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
                    style: SpotType.body.copyWith(
                      color: SpotColors.textPrimary,
                    ),
                    onChanged: _onSearchChanged,
                    onSubmitted: (_) => _submitSearch(),
                  ),
                ),
              ],
            ),
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
    return SpotTabbedScreenTabBar(
      controller: _tabController,
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
    final roots = visibleDiscoverThreads(
      posts,
      query: _searchQuery,
      excludedAuthorPubkey: widget.wallet.publicKeyHex,
    );
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
                  useFeedEdgeSwipeMediaLayout: true,
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

class DiscoverSearchResultsScreen extends StatefulWidget {
  const DiscoverSearchResultsScreen({
    super.key,
    required this.wallet,
    required this.initialQuery,
    this.initialPosts = const [],
    this.persistedPostsLoader,
    this.profileSearch,
    this.eventStreamFactory,
  });

  final WalletModel wallet;
  final String initialQuery;
  final List<MediaPost> initialPosts;
  final Future<List<MediaPost>> Function()? persistedPostsLoader;
  final Future<List<ProfileModel>> Function(String query)? profileSearch;
  final Stream<CivicEvent> Function()? eventStreamFactory;

  @override
  State<DiscoverSearchResultsScreen> createState() =>
      _DiscoverSearchResultsScreenState();
}

class _DiscoverSearchResultsScreenState
    extends State<DiscoverSearchResultsScreen>
    with SingleTickerProviderStateMixin {
  late final EventRepository _repo;
  late final TabController _tabController;
  StreamSubscription<CivicEvent>? _sub;

  List<MediaPost> _posts = [];
  List<ProfileModel> _profiles = [];
  final Set<String> _loadingMediaPostIds = {};
  bool _isLoadingPosts = true;
  bool _isLoadingProfiles = false;

  bool get _usesTabbedLayout =>
      discoverSearchResultUsesTabbedLayout(widget.initialQuery);

  String get _queryLabel => widget.initialQuery.trim();

  @override
  void initState() {
    super.initState();
    _repo = EventRepository();
    _tabController = TabController(length: 2, vsync: this);
    _posts = List<MediaPost>.from(widget.initialPosts);
    _initFeed();
    if (_usesTabbedLayout) {
      unawaited(_loadProfiles());
    }
  }

  @override
  void dispose() {
    _sub?.cancel();
    _tabController.dispose();
    _repo.dispose();
    super.dispose();
  }

  Future<void> _initFeed() async {
    setState(() => _isLoadingPosts = true);
    try {
      await _loadPersistedPosts();
      _sub = (widget.eventStreamFactory?.call() ?? _repo.subscribeToEvents())
          .listen(_onEvent);
    } catch (_) {
    } finally {
      if (mounted) {
        setState(() => _isLoadingPosts = false);
      }
    }
  }

  Future<void> _loadPersistedPosts() async {
    final persisted =
        await (widget.persistedPostsLoader ?? LocalPostStore.instance.loadPosts)
            .call();
    if (!mounted || persisted.isEmpty) return;
    setState(() => _posts = _mergePosts(_posts, persisted));
  }

  Future<void> _loadProfiles() async {
    setState(() => _isLoadingProfiles = true);
    try {
      final profiles =
          await (widget.profileSearch ??
                  MetadataService.instance.searchProfiles)
              .call(widget.initialQuery);
      if (!mounted) return;
      setState(() {
        _profiles = profiles
            .where((profile) {
              final pubkey = profile.legacyPubkey?.trim();
              return pubkey != null &&
                  pubkey.isNotEmpty &&
                  pubkey != widget.wallet.publicKeyHex;
            })
            .toList(growable: false);
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _profiles = const []);
    } finally {
      if (mounted) {
        setState(() => _isLoadingProfiles = false);
      }
    }
  }

  void _onEvent(CivicEvent event) {
    if (!mounted) return;
    final merged = _mergePosts(_posts, event.posts);
    if (orderedPostsEqual(merged, _posts)) return;
    unawaited(LocalPostStore.instance.savePosts(event.posts));
    setState(() => _posts = merged);
  }

  List<MediaPost> _mergePosts(
    List<MediaPost> current,
    Iterable<MediaPost> incoming,
  ) => mergePostsPreservingLocalState(current, incoming);

  Future<void> _refresh() async {
    await _sub?.cancel();
    _repo.reset();
    setState(() => _posts = List<MediaPost>.from(widget.initialPosts));
    await _initFeed();
    if (_usesTabbedLayout) {
      await _loadProfiles();
    }
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

  void _openThread(BuildContext context, MediaPost post) {
    Navigator.of(context).push(
      buildThreadScreenRoute(
        rootPostId: post.nostrEventId,
        initialPosts: _posts,
        wallet: widget.wallet,
        eventRepo: _repo,
      ),
    );
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

  void _openDiscoverTag(String tag) {
    Navigator.of(context).push(
      buildDiscoverSearchResultsRoute(
        wallet: widget.wallet,
        query: '#$tag',
        initialPosts: _posts,
        persistedPostsLoader: widget.persistedPostsLoader,
        profileSearch: widget.profileSearch,
        eventStreamFactory: widget.eventStreamFactory,
      ),
    );
  }

  Widget _buildLoadingState() {
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

  Widget _buildHeader() {
    return Padding(
      padding: spotTabbedScreenHeaderPadding,
      child: SizedBox(
        height: spotTabbedScreenHeaderRowHeight,
        child: Row(
          children: [
            IconButton(
              onPressed: () => Navigator.of(context).maybePop(),
              icon: const Icon(CupertinoIcons.back, size: 20),
              color: SpotColors.textSecondary,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints.tightFor(width: 28, height: 28),
            ),
            const SizedBox(width: SpotSpacing.sm),
            Expanded(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: SpotSpacing.md),
                decoration: SpotDecoration.input(radius: SpotRadius.full),
                child: Row(
                  children: [
                    const Icon(
                      CupertinoIcons.search,
                      size: 16,
                      color: SpotColors.textSecondary,
                    ),
                    const SizedBox(width: SpotSpacing.sm),
                    Expanded(
                      child: Text(
                        _queryLabel,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: SpotType.body,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildThreadsTab() {
    final roots = visibleDiscoverThreads(
      _posts,
      query: widget.initialQuery,
      excludedAuthorPubkey: widget.wallet.publicKeyHex,
    );

    if (_isLoadingPosts && roots.isEmpty) {
      return _buildLoadingState();
    }

    if (roots.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(SpotSpacing.xxxl),
          child: Text(
            'No threads found for "$_queryLabel"',
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
      child: ListView.builder(
        padding: const EdgeInsets.only(
          top: SpotSpacing.sm,
          bottom: SpotSpacing.xl,
        ),
        itemCount: roots.length,
        itemBuilder: (ctx, i) {
          final post = roots[i];
          return InkWell(
            onTap: () => _openThread(ctx, post),
            child: PostThreadRow(
              post: post,
              isLast: true,
              useFeedEdgeSwipeMediaLayout: true,
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
      ),
    );
  }

  Widget _buildUsersTab() {
    if (_isLoadingProfiles) {
      return _buildLoadingState();
    }

    if (_profiles.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(SpotSpacing.xxxl),
          child: Text(
            'No users found for "$_queryLabel"',
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
      child: ListView.separated(
        padding: const EdgeInsets.only(
          top: SpotSpacing.sm,
          bottom: SpotSpacing.xl,
        ),
        itemCount: _profiles.length,
        separatorBuilder: (_, index) => const Divider(
          height: 1,
          thickness: 0.5,
          color: SpotColors.borderSubtle,
        ),
        itemBuilder: (context, index) {
          final profile = _profiles[index];
          final pubkey = profile.legacyPubkey!.trim();
          final secondaryText = discoverProfileSearchSecondaryText(profile);

          return InkWell(
            onTap: () => _openUserProfile(context, pubkey),
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: SpotSpacing.lg,
                vertical: SpotSpacing.md,
              ),
              child: Row(
                children: [
                  ProfileAvatar(
                    pubkey: pubkey,
                    avatarContentHash: profile.avatarContentHash,
                    size: 48,
                  ),
                  const SizedBox(width: SpotSpacing.lg),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          discoverProfileSearchDisplayName(profile),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: SpotType.subheading,
                        ),
                        if (secondaryText != null) ...[
                          const SizedBox(height: SpotSpacing.xs),
                          Text(
                            secondaryText,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: SpotType.bodySecondary,
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(width: SpotSpacing.md),
                  const Icon(
                    CupertinoIcons.chevron_right,
                    size: 16,
                    color: SpotColors.textTertiary,
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      bottom: false,
      child: Column(
        children: [
          _buildHeader(),
          if (_usesTabbedLayout)
            SpotTabbedScreenTabBar(
              controller: _tabController,
              tabs: const [
                Tab(text: 'THREADS'),
                Tab(text: 'USERS'),
              ],
            ),
          Expanded(
            child: _usesTabbedLayout
                ? TabBarView(
                    controller: _tabController,
                    children: [_buildThreadsTab(), _buildUsersTab()],
                  )
                : _buildThreadsTab(),
          ),
        ],
      ),
    );
  }
}
