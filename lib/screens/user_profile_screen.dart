import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import 'package:mobile/features/event/event_repository.dart';
import 'package:mobile/features/metadata/metadata_service.dart';
import 'package:mobile/models/event_model.dart';
import 'package:mobile/models/follow_stats.dart';
import 'package:mobile/models/media_post.dart';
import 'package:mobile/models/profile_model.dart';
import 'package:mobile/models/wallet_model.dart';
import 'package:mobile/screens/discover_screen.dart';
import 'package:mobile/screens/post_composer_screen.dart';
import 'package:mobile/screens/thread_screen.dart';
import 'package:mobile/services/follow_service.dart';
import 'package:mobile/services/local_post_store.dart';
import 'package:mobile/services/post_merge.dart';
import 'package:mobile/services/post_thread_ordering.dart';
import 'package:mobile/theme/spot_theme.dart';
import 'package:mobile/widgets/profile_avatar.dart';
import 'package:mobile/widgets/profile_activity_summary.dart';
import 'package:mobile/widgets/profile_stats_row.dart';
import 'package:mobile/widgets/profile_thread_tab_bar.dart';
import 'package:mobile/widgets/post_thread_row.dart';

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
  StreamSubscription<CivicEvent>? _sub;
  late final TabController _contentTabController;

  List<MediaPost> _posts = [];
  bool _isLoading = true;
  bool _isFollowing = false;
  bool _isTogglingFollow = false;
  ProfileModel? _profile;
  FollowStats _followStats = const FollowStats.empty();

  @override
  void initState() {
    super.initState();
    _repo = EventRepository();
    _contentTabController = TabController(length: 2, vsync: this)
      ..addListener(() {
        if (mounted) setState(() {});
      });
    _initFeed();
    _loadProfile();
  }

  @override
  void dispose() {
    _sub?.cancel();
    _contentTabController.dispose();
    _repo.dispose();
    super.dispose();
  }

  // ── Data loading ──────────────────────────────────────────────────────────

  Future<void> _initFeed() async {
    setState(() => _isLoading = true);
    try {
      await _loadPersistedPosts();
      _sub = _repo.subscribeToAuthorPosts(widget.pubkey).listen(_onEvent);
    } catch (_) {
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _onEvent(CivicEvent event) {
    if (!mounted) return;
    final posts = event.posts.where((p) => p.pubkey == widget.pubkey).toList();
    if (posts.isEmpty) return;
    final merged = _mergePosts(_posts, posts);
    if (orderedPostsEqual(merged, _posts)) return;
    unawaited(LocalPostStore.instance.savePosts(posts));
    setState(() => _posts = merged);
  }

  Future<void> _refresh() async {
    await _sub?.cancel();
    _repo.reset();
    setState(() => _posts = []);
    await _initFeed();
    await _loadProfile();
  }

  List<MediaPost> _mergePosts(
    List<MediaPost> current,
    Iterable<MediaPost> incoming,
  ) => mergePostsPreservingLocalState(current, incoming);

  Future<void> _loadPersistedPosts() async {
    final persisted = await LocalPostStore.instance.loadPosts(
      authorPubkey: widget.pubkey,
    );
    if (!mounted || persisted.isEmpty) return;
    setState(() => _posts = _mergePosts(_posts, persisted));
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
    setState(() => _posts = replacePostsById(_posts, [post]));
    unawaited(LocalPostStore.instance.savePost(post));
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
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Follow update failed: $e')));
    } finally {
      if (mounted) {
        setState(() => _isTogglingFollow = false);
      }
    }
  }

  // ── Post action ───────────────────────────────────────────────────────────

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
                  isMuted ? 'Unmute user' : 'Mute user',
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
                  isBlocked ? 'Unblock user' : 'Block user',
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
                title: const Text(
                  'Report user',
                  style: TextStyle(color: SpotColors.warning),
                ),
                contentPadding: EdgeInsets.zero,
                onTap: () {
                  Navigator.of(ctx).pop();
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('User reported.')),
                  );
                },
              ),
              // Cancel
              ListTile(
                leading: const Icon(
                  CupertinoIcons.xmark,
                  color: SpotColors.textTertiary,
                  size: 20,
                ),
                title: const Text(
                  'Cancel',
                  style: TextStyle(color: SpotColors.textTertiary),
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
    final threads = topLevelThreadPosts(_posts);
    final replies = replyPosts(_posts);
    final showReplies = _contentTabController.index == 1;
    final visiblePosts = showReplies ? replies : threads;
    final emptyTitle = showReplies ? 'No replies yet' : 'No threads yet';
    final activitySummary = buildProfileActivitySummary(
      posts: _posts,
      accountCreatedAt: _profile?.createdAt,
    );
    return Scaffold(
      backgroundColor: SpotColors.bg,
      appBar: AppBar(
        backgroundColor: SpotColors.bg,
        title: Text(
          _profile?.displayName?.trim().isNotEmpty == true
              ? _profile!.displayName!.trim()
              : 'Citizen',
          style: SpotType.subheading,
        ),
        actions: [
          IconButton(
            icon: const Icon(CupertinoIcons.ellipsis, size: 20),
            color: SpotColors.textSecondary,
            tooltip: 'User options',
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
                postCount: _posts.length,
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
            if (_isLoading && visiblePosts.isEmpty)
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
                            ? 'Replies from this account will appear here'
                            : 'No top-level threads from this account yet',
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
                    child: PostThreadRow(
                      post: post,
                      isLast: true,
                      onTagTap: (tag) => _openDiscoverTag(ctx, tag),
                      onReport: () => _reportPost(post),
                      onLike: () => _toggleLike(post),
                      onMediaUpdated: _updateMediaPost,
                      onReply: () => showPostComposer(
                        ctx,
                        wallet: widget.wallet,
                        replyToPost: post,
                        onPublished: (reply) {
                          if (!mounted) return;
                          setState(() => _posts = _mergePosts(_posts, [reply]));
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
                ),
              ),
            ],
          ),
          const SizedBox(height: SpotSpacing.md),
          Text(
            profile?.displayName?.trim().isNotEmpty == true
                ? profile!.displayName!.trim()
                : 'Citizen',
            style: SpotType.subheading,
          ),
          const SizedBox(height: SpotSpacing.md),
          ProfileActivitySummaryCard(summary: activitySummary),
          const SizedBox(height: SpotSpacing.lg),
          SizedBox(
            width: double.infinity,
            child: isFollowing
                ? OutlinedButton(
                    onPressed: isTogglingFollow ? null : onFollowTap,
                    child: Text(isTogglingFollow ? 'Updating…' : 'Following'),
                  )
                : FilledButton(
                    onPressed: isTogglingFollow ? null : onFollowTap,
                    child: Text(isTogglingFollow ? 'Updating…' : 'Follow'),
                  ),
          ),
        ],
      ),
    );
  }
}
