import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import 'package:mobile/features/event/event_repository.dart';
import 'package:mobile/l10n/app_localizations.dart';
import 'package:mobile/features/metadata/metadata_service.dart';
import 'package:mobile/features/p2p/p2p_service.dart';
import 'package:mobile/models/follow_stats.dart';
import 'package:mobile/models/media_post.dart';
import 'package:mobile/models/profile_model.dart';
import 'package:mobile/models/wallet_model.dart';
import 'package:mobile/screens/discover_screen.dart';
import 'package:mobile/screens/post_composer_screen.dart';
import 'package:mobile/screens/thread_screen.dart';
import 'package:mobile/services/app_data_reset_service.dart';
import 'package:mobile/services/follow_service.dart';
import 'package:mobile/services/local_post_store.dart';
import 'package:mobile/services/media_resolver.dart';
import 'package:mobile/services/media_sync_service.dart';
import 'package:mobile/services/post_merge.dart';
import 'package:mobile/services/post_thread_ordering.dart';
import 'package:mobile/theme/spot_theme.dart';
import 'package:mobile/widgets/profile_avatar.dart';
import 'package:mobile/widgets/profile_activity_summary.dart';
import 'package:mobile/widgets/profile_post_thread_row.dart';
import 'package:mobile/widgets/profile_stats_row.dart';
import 'package:mobile/widgets/footprint_map_tab.dart';
import 'package:mobile/widgets/profile_thread_tab_bar.dart';
import 'package:mobile/widgets/user_report_sheet.dart';

/// Profile screen for any user other than the local account.
///
/// Provides Follow / Unfollow and a settings menu for Mute / Block / Report.
class UserProfileScreen extends StatefulWidget {
  const UserProfileScreen({
    super.key,
    required this.pubkey,
    required this.wallet,
  });

  final String pubkey;
  final WalletModel wallet;

  @override
  State<UserProfileScreen> createState() => _UserProfileScreenState();
}

class _UserProfileScreenState extends State<UserProfileScreen>
    with SingleTickerProviderStateMixin {
  late final EventRepository _repo;
  StreamSubscription<void>? _repoSub;
  StreamSubscription<void>? _resetSub;
  late final TabController _contentTabController;

  List<MediaPost> _posts = [];
  List<MediaPost> _remotePosts = [];
  List<MediaPost> _persistedPosts = [];
  final Set<String> _loadingMediaPostIds = {};
  bool _isLoading = true;
  bool _isFollowing = false;
  bool _isTogglingFollow = false;
  ProfileModel? _profile;
  FollowStats _followStats = const FollowStats.empty();

  @override
  void initState() {
    super.initState();
    _repo = EventRepository();
    _contentTabController = TabController(length: 3, vsync: this)
      ..addListener(() {
        if (mounted) setState(() {});
      });
    _resetSub ??= AppDataResetService.instance.localDataCleared.listen((_) {
      unawaited(_handleLocalDataCleared());
    });
    _initFeed();
    _loadProfile();
  }

  @override
  void dispose() {
    _repoSub?.cancel();
    _resetSub?.cancel();
    _contentTabController.dispose();
    _repo.dispose();
    super.dispose();
  }

  // ── Data loading ──────────────────────────────────────────────────────────

  Future<void> _initFeed() async {
    setState(() => _isLoading = true);
    try {
      await _loadPersistedPosts();
      _repoSub ??= _repo
          .subscribeToAuthorChanges(widget.pubkey)
          .listen((_) => _onRepoChanged());
      _onRepoChanged();
    } catch (_) {
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _onRepoChanged() {
    if (!mounted) return;
    final nextRemotePosts = _repo.getPostsForAuthor(widget.pubkey);
    final remoteChanged = !orderedPostsEqual(nextRemotePosts, _remotePosts);
    _remotePosts = nextRemotePosts;
    if (remoteChanged && nextRemotePosts.isNotEmpty) {
      unawaited(LocalPostStore.instance.savePosts(nextRemotePosts));
    }
    _syncVisiblePosts();
  }

  Future<void> _refresh() async {
    setState(() {
      _isLoading = true;
      _remotePosts = [];
      _posts = [];
    });
    try {
      await _loadPersistedPosts();
      await _repo.refresh();
      await _loadProfile();
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _loadPersistedPosts() async {
    final persisted = await LocalPostStore.instance.loadPosts(
      authorPubkey: widget.pubkey,
    );
    _persistedPosts = persisted;
    _syncVisiblePosts();
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

  Future<void> _loadProfile() async {
    try {
      await FollowService.instance.init();
      final profile = await MetadataService.instance.fetchProfileByPubkey(
        widget.pubkey,
      );
      final stats = await MetadataService.instance.fetchFollowStatsByPubkey(
        widget.pubkey,
      );
      if (!mounted) return;
      final normalizedDisplayName = profile?.displayName?.trim();
      setState(() {
        _profile = profile;
        _followStats = stats ?? const FollowStats.empty();
        _isFollowing =
            stats?.isFollowingByMe ??
            FollowService.instance.isFollowing(widget.pubkey);
        _posts = _posts
            .map(
              (post) => post.pubkey == widget.pubkey
                  ? post.copyWith(
                      authorDisplayName:
                          normalizedDisplayName?.isNotEmpty == true
                          ? normalizedDisplayName
                          : null,
                      authorAvatarContentHash: profile?.avatarContentHash,
                    )
                  : post,
            )
            .toList(growable: false);
      });
    } catch (e) {
      debugPrint('[UserProfileScreen] Failed to load profile: $e');
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

  void _openProfileThread(BuildContext context, MediaPost post) {
    final rootPostId = post.replyToId == null
        ? post.nostrEventId
        : visibleThreadRootIdForPost(_posts, post.nostrEventId);
    Navigator.of(context).push(
      buildThreadScreenRoute(
        rootPostId: rootPostId,
        initialPosts: _posts,
        wallet: widget.wallet,
      ),
    );
  }

  // ── Follow ────────────────────────────────────────────────────────────────

  Future<void> _toggleFollow() async {
    if (_isTogglingFollow) return;
    final l10n = AppLocalizations.of(context)!;
    setState(() => _isTogglingFollow = true);
    final shouldFollow = !_isFollowing;
    try {
      final stats = await MetadataService.instance.setFollowingForPubkey(
        targetPubkey: widget.pubkey,
        shouldFollow: shouldFollow,
        wallet: widget.wallet,
      );
      if (shouldFollow) {
        await FollowService.instance.follow(widget.pubkey);
      } else {
        await FollowService.instance.unfollow(widget.pubkey);
      }
      if (!mounted) return;
      setState(() {
        _isFollowing = shouldFollow;
        _followStats = stats;
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.followUpdateFailed(e.toString()))),
      );
    } finally {
      if (mounted) {
        setState(() => _isTogglingFollow = false);
      }
    }
  }

  // ── Post action ───────────────────────────────────────────────────────────

  Future<void> _reportPost(MediaPost post) async {
    final l10n = AppLocalizations.of(context)!;
    try {
      await MetadataService.instance.reportContent(
        postId: post.nostrEventId,
        contentHash: post.contentHash,
        reason: 'harmful',
        wallet: widget.wallet,
      );
      setState(() => _posts = _posts.where((p) => p.id != post.id).toList());
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(l10n.reportedContentHidden)));
      }
    } catch (_) {}
  }

  Future<void> _reportUser() async {
    final l10n = AppLocalizations.of(context)!;
    final wasBlocked = FollowService.instance.isBlocked(widget.pubkey);
    final didSubmit = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: SpotColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(SpotRadius.lg),
        ),
      ),
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
        child: UserReportSheet(
          onSubmit: (reason, details) {
            return MetadataService.instance.reportUser(
              reportedPubkey: widget.pubkey,
              reason: reason.storageValue,
              wallet: widget.wallet,
              details: details,
            );
          },
        ),
      ),
    );

    if (didSubmit != true || !mounted) return;

    final messenger = ScaffoldMessenger.of(context);
    if (wasBlocked || FollowService.instance.isBlocked(widget.pubkey)) {
      messenger.showSnackBar(SnackBar(content: Text(l10n.userReported)));
      return;
    }

    messenger.showSnackBar(
      SnackBar(
        content: Text(l10n.userReported),
        action: SnackBarAction(
          label: l10n.blockUser,
          onPressed: () {
            unawaited(_blockUserFromReportAction());
          },
        ),
      ),
    );
  }

  Future<void> _blockUserFromReportAction() async {
    await FollowService.instance.block(widget.pubkey);
    if (!mounted) return;
    Navigator.of(context).pop();
  }

  void _openDiscoverTag(BuildContext ctx, String tag) {
    Navigator.of(ctx).push(
      buildDiscoverScreenRoute(
        wallet: widget.wallet,
        initialSearchQuery: '#$tag',
      ),
    );
  }

  // ── User settings menu ────────────────────────────────────────────────────

  void _showUserMenu() {
    final l10n = AppLocalizations.of(context)!;
    final isMuted = FollowService.instance.isMuted(widget.pubkey);
    final isBlocked = FollowService.instance.isBlocked(widget.pubkey);

    showModalBottomSheet<void>(
      context: context,
      backgroundColor: SpotColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(SpotRadius.lg),
        ),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: SpotSpacing.lg,
            vertical: SpotSpacing.md,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Handle
              Container(
                width: 36,
                height: 4,
                margin: const EdgeInsets.only(bottom: SpotSpacing.lg),
                decoration: BoxDecoration(
                  color: SpotColors.border,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              // Mute / Unmute
              ListTile(
                leading: Icon(
                  isMuted
                      ? CupertinoIcons.speaker
                      : CupertinoIcons.speaker_slash,
                  color: SpotColors.textSecondary,
                  size: 20,
                ),
                title: Text(
                  isMuted ? l10n.unmuteUser : l10n.muteUser,
                  style: const TextStyle(color: SpotColors.textSecondary),
                ),
                contentPadding: EdgeInsets.zero,
                onTap: () async {
                  Navigator.of(ctx).pop();
                  if (isMuted) {
                    await FollowService.instance.unmute(widget.pubkey);
                  } else {
                    await FollowService.instance.mute(widget.pubkey);
                    if (_isFollowing && mounted) {
                      setState(() => _isFollowing = false);
                    }
                  }
                  if (mounted) setState(() {});
                },
              ),
              // Block / Unblock
              ListTile(
                leading: Icon(
                  isBlocked
                      ? CupertinoIcons.checkmark_circle
                      : CupertinoIcons.xmark_circle,
                  color: SpotColors.danger,
                  size: 20,
                ),
                title: Text(
                  isBlocked ? l10n.unblockUser : l10n.blockUser,
                  style: const TextStyle(color: SpotColors.danger),
                ),
                contentPadding: EdgeInsets.zero,
                onTap: () async {
                  Navigator.of(ctx).pop();
                  if (isBlocked) {
                    await FollowService.instance.unblock(widget.pubkey);
                    if (mounted) setState(() {});
                  } else {
                    await FollowService.instance.block(widget.pubkey);
                    if (mounted) Navigator.of(context).pop();
                  }
                },
              ),
              // Report user
              ListTile(
                leading: const Icon(
                  CupertinoIcons.flag,
                  color: SpotColors.warning,
                  size: 20,
                ),
                title: Text(
                  l10n.reportUser,
                  style: const TextStyle(color: SpotColors.warning),
                ),
                contentPadding: EdgeInsets.zero,
                onTap: () {
                  Navigator.of(ctx).pop();
                  unawaited(_reportUser());
                },
              ),
              // Cancel
              ListTile(
                leading: const Icon(
                  CupertinoIcons.xmark,
                  color: SpotColors.textTertiary,
                  size: 20,
                ),
                title: Text(
                  l10n.cancelAction,
                  style: const TextStyle(color: SpotColors.textTertiary),
                ),
                contentPadding: EdgeInsets.zero,
                onTap: () => Navigator.of(ctx).pop(),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final threads = topLevelThreadPosts(_posts);
    final replies = replyPosts(_posts);
    final hasVisibilitySettings = _profile != null;
    final threadsPublic = _profile?.areThreadsPublic ?? true;
    final repliesPublic = _profile?.areRepliesPublic ?? true;
    final footprintMapPublic = _profile?.isFootprintMapPublic ?? false;
    final publicProfilePosts = <MediaPost>[
      if (!hasVisibilitySettings || threadsPublic) ...threads,
      if (!hasVisibilitySettings || repliesPublic) ...replies,
    ];
    final tabIndex = _contentTabController.index;
    final showReplies = tabIndex == 1;
    final showMap = tabIndex == 2;
    final threadsHidden =
        hasVisibilitySettings && !showReplies && !showMap && !threadsPublic;
    final repliesHidden =
        hasVisibilitySettings && showReplies && !repliesPublic;
    final mapHidden = hasVisibilitySettings && showMap && !footprintMapPublic;
    final visiblePosts = showReplies
        ? (repliesHidden ? const <MediaPost>[] : replies)
        : (threadsHidden ? const <MediaPost>[] : threads);
    final emptyTitle = showReplies ? l10n.noRepliesYet : l10n.noThreadsYet;
    final activitySummary = buildProfileActivitySummary(
      posts: publicProfilePosts,
      accountCreatedAt: _profile?.createdAt,
    );
    return Scaffold(
      backgroundColor: SpotColors.bg,
      appBar: AppBar(
        backgroundColor: SpotColors.bg,
        title: Text(
          _profile?.displayName?.trim().isNotEmpty == true
              ? _profile!.displayName!.trim()
              : l10n.citizenDefaultName,
          style: SpotType.subheading,
        ),
        actions: [
          IconButton(
            icon: const Icon(CupertinoIcons.ellipsis, size: 20),
            color: SpotColors.textSecondary,
            tooltip: l10n.userOptionsTitle,
            onPressed: _showUserMenu,
          ),
        ],
      ),
      body: RefreshIndicator(
        color: SpotColors.accent,
        backgroundColor: SpotColors.surface,
        displacement: 28,
        onRefresh: _refresh,
        child: CustomScrollView(
          slivers: [
            SliverToBoxAdapter(
              child: _UserProfileHeader(
                pubkey: widget.pubkey,
                postCount: publicProfilePosts.length,
                followStats: _followStats,
                isFollowing: _isFollowing,
                isTogglingFollow: _isTogglingFollow,
                onFollowTap: _toggleFollow,
                profile: _profile,
                activitySummary: activitySummary,
              ),
            ),
            const SliverToBoxAdapter(child: Divider(height: 1, thickness: 0.5)),
            SliverToBoxAdapter(
              child: ProfileThreadTabBar(controller: _contentTabController),
            ),
            if (threadsHidden)
              SliverFillRemaining(
                child: _PrivateProfileSection(
                  title: l10n.threadsArePrivateTitle,
                  subtitle: l10n.threadsPrivate,
                ),
              )
            else if (repliesHidden)
              SliverFillRemaining(
                child: _PrivateProfileSection(
                  title: l10n.repliesArePrivateTitle,
                  subtitle: l10n.repliesPrivate,
                ),
              )
            else if (mapHidden)
              SliverFillRemaining(
                child: _PrivateProfileSection(
                  title: l10n.footprintMapIsPrivateTitle,
                  subtitle: l10n.footprintMapPrivate,
                ),
              )
            else if (showMap)
              SliverLayoutBuilder(
                builder: (context, constraints) => SliverToBoxAdapter(
                  child: SizedBox(
                    height: constraints.remainingPaintExtent,
                    child: FootprintMapTab(posts: _posts),
                  ),
                ),
              )
            else if (_isLoading && visiblePosts.isEmpty)
              const SliverFillRemaining(
                child: Center(
                  child: SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      color: SpotColors.accent,
                      strokeWidth: 1,
                    ),
                  ),
                ),
              )
            else if (visiblePosts.isEmpty)
              SliverFillRemaining(
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        CupertinoIcons.camera,
                        color: SpotColors.overlay,
                        size: 32,
                      ),
                      const SizedBox(height: SpotSpacing.lg),
                      Text(emptyTitle, style: SpotType.bodySecondary),
                      const SizedBox(height: SpotSpacing.xs),
                      Text(
                        showReplies
                            ? l10n.repliesFromAccountHint
                            : l10n.noTopLevelThreadsHint,
                        style: SpotType.caption,
                      ),
                    ],
                  ),
                ),
              )
            else
              SliverList(
                delegate: SliverChildBuilderDelegate((ctx, i) {
                  final post = visiblePosts[i];
                  return InkWell(
                    onTap: () => _openProfileThread(ctx, post),
                    child: ProfilePostThreadRow(
                      post: post,
                      onTagTap: (tag) => _openDiscoverTag(ctx, tag),
                      onReport: () => _reportPost(post),
                      onLike: () => _toggleLike(post),
                      isMediaLoading: _loadingMediaPostIds.contains(post.id),
                      onMediaUpdated: _hydrateMediaPost,
                      onReply: () => showPostComposer(
                        ctx,
                        wallet: widget.wallet,
                        replyToPost: post,
                        onPublished: (reply) {
                          if (!mounted) return;
                          setState(
                            () => _posts = mergePostsPreservingLocalState(
                              _posts,
                              [reply],
                            ),
                          );
                        },
                      ),
                    ),
                  );
                }, childCount: visiblePosts.length),
              ),
          ],
        ),
      ),
    );
  }
}

class _PrivateProfileSection extends StatelessWidget {
  const _PrivateProfileSection({required this.title, required this.subtitle});

  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: SpotSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              CupertinoIcons.lock_circle,
              color: SpotColors.overlay,
              size: 36,
            ),
            const SizedBox(height: SpotSpacing.lg),
            Text(title, style: SpotType.bodySecondary),
            const SizedBox(height: SpotSpacing.xs),
            Text(
              subtitle,
              textAlign: TextAlign.center,
              style: SpotType.caption,
            ),
          ],
        ),
      ),
    );
  }
}

// ── Profile header ────────────────────────────────────────────────────────────

class _UserProfileHeader extends StatelessWidget {
  const _UserProfileHeader({
    required this.pubkey,
    required this.postCount,
    required this.followStats,
    required this.isFollowing,
    required this.isTogglingFollow,
    required this.onFollowTap,
    required this.profile,
    required this.activitySummary,
  });

  final String pubkey;
  final int postCount;
  final FollowStats followStats;
  final bool isFollowing;
  final bool isTogglingFollow;
  final VoidCallback onFollowTap;
  final ProfileModel? profile;
  final ProfileActivitySummary activitySummary;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        SpotSpacing.lg,
        SpotSpacing.xl,
        SpotSpacing.lg,
        SpotSpacing.lg,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              ProfileAvatar(
                pubkey: pubkey,
                avatarContentHash: profile?.avatarContentHash,
                size: 72,
              ),
              const SizedBox(width: SpotSpacing.lg),
              Expanded(
                child: ProfileStatsRow(
                  postCount: postCount,
                  followingCount: followStats.followingCount,
                  followerCount: followStats.followerCount,
                  joinedAt: activitySummary.accountCreatedAt,
                  lastThreadAt: activitySummary.lastThreadAt,
                  lastReplyAt: activitySummary.lastReplyAt,
                ),
              ),
            ],
          ),
          const SizedBox(height: SpotSpacing.md),
          Text(
            profile?.displayName?.trim().isNotEmpty == true
                ? profile!.displayName!.trim()
                : l10n.citizenDefaultName,
            style: SpotType.subheading,
          ),
          if (profile?.description?.trim().isNotEmpty == true) ...[
            const SizedBox(height: SpotSpacing.xs),
            Text(profile!.description!.trim(), style: SpotType.bodySecondary),
          ],
          const SizedBox(height: SpotSpacing.md),
          ProfileLocationChips(summary: activitySummary),
          const SizedBox(height: SpotSpacing.lg),
          SizedBox(
            width: double.infinity,
            child: isFollowing
                ? OutlinedButton(
                    onPressed: isTogglingFollow ? null : onFollowTap,
                    child: Text(
                      isTogglingFollow
                          ? l10n.updatingLabel
                          : l10n.followingLabel,
                    ),
                  )
                : FilledButton(
                    onPressed: isTogglingFollow ? null : onFollowTap,
                    child: Text(
                      isTogglingFollow ? l10n.updatingLabel : l10n.followButton,
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}
