import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import 'package:mobile/features/event/event_repository.dart';
import 'package:mobile/features/nostr/nostr_service.dart';
import 'package:mobile/models/event_model.dart';
import 'package:mobile/models/media_post.dart';
import 'package:mobile/models/wallet_model.dart';
import 'package:mobile/screens/post_composer_screen.dart';
import 'package:mobile/screens/thread_screen.dart';
import 'package:mobile/services/follow_service.dart';
import 'package:mobile/services/local_post_store.dart';
import 'package:mobile/services/post_merge.dart';
import 'package:mobile/services/post_thread_ordering.dart';
import 'package:mobile/theme/spot_theme.dart';
import 'package:mobile/widgets/post_thread_row.dart';

/// Profile screen for any user other than the local account.
///
/// Provides Follow / Unfollow and a settings menu for Mute / Block / Report.
class UserProfileScreen extends StatefulWidget {
  const UserProfileScreen({
    super.key,
    required this.pubkey,
    required this.wallet,
    required this.nostrService,
  });

  final String pubkey;
  final WalletModel wallet;
  final NostrService nostrService;

  @override
  State<UserProfileScreen> createState() => _UserProfileScreenState();
}

class _UserProfileScreenState extends State<UserProfileScreen> {
  late final EventRepository _repo;
  StreamSubscription<CivicEvent>? _sub;

  List<MediaPost> _posts = [];
  bool _isLoading = true;
  bool _isFollowing = false;

  @override
  void initState() {
    super.initState();
    _repo = EventRepository(nostrService: widget.nostrService);
    _isFollowing = FollowService.instance.isFollowing(widget.pubkey);
    _initFeed();
  }

  @override
  void dispose() {
    _sub?.cancel();
    _repo.dispose();
    super.dispose();
  }

  // ── Data loading ──────────────────────────────────────────────────────────

  Future<void> _initFeed() async {
    setState(() => _isLoading = true);
    try {
      await _loadPersistedPosts();
      await widget.nostrService.connect();
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

  void _toggleLike(MediaPost post) {
    final updated = post.copyWith(isLikedByMe: !post.isLikedByMe);
    setState(() => _posts = replacePostsById(_posts, [updated]));
    unawaited(LocalPostStore.instance.setLikedByMe(post, updated.isLikedByMe));
  }

  void _updateMediaPost(MediaPost post) {
    setState(() => _posts = replacePostsById(_posts, [post]));
    unawaited(LocalPostStore.instance.savePost(post));
  }

  // ── Follow ────────────────────────────────────────────────────────────────

  Future<void> _toggleFollow() async {
    if (_isFollowing) {
      await FollowService.instance.unfollow(widget.pubkey);
    } else {
      await FollowService.instance.follow(widget.pubkey);
    }
    if (mounted) setState(() => _isFollowing = !_isFollowing);
  }

  // ── Post action ───────────────────────────────────────────────────────────

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
    final roots = topLevelThreadPosts(_posts);
    return Scaffold(
      backgroundColor: SpotColors.bg,
      appBar: AppBar(
        backgroundColor: SpotColors.bg,
        title: Text(_shortKey(widget.pubkey), style: SpotType.mono),
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
                isFollowing: _isFollowing,
                onFollowTap: _toggleFollow,
              ),
            ),
            const SliverToBoxAdapter(child: Divider(height: 1, thickness: 0.5)),
            if (_isLoading && _posts.isEmpty)
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
            else if (_posts.isEmpty)
              const SliverFillRemaining(
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        CupertinoIcons.camera,
                        color: SpotColors.overlay,
                        size: 32,
                      ),
                      SizedBox(height: SpotSpacing.lg),
                      Text('No posts yet', style: SpotType.bodySecondary),
                    ],
                  ),
                ),
              )
            else
              SliverList(
                delegate: SliverChildBuilderDelegate((ctx, i) {
                  final post = roots[i];
                  return InkWell(
                    onTap: () => Navigator.of(ctx).push(
                      buildThreadScreenRoute(
                        rootPostId: post.nostrEventId,
                        initialPosts: _posts,
                        wallet: widget.wallet,
                        nostrService: widget.nostrService,
                      ),
                    ),
                    child: PostThreadRow(
                      post: post,
                      isLast: true,
                      onReport: () => _reportPost(post),
                      onLike: () => _toggleLike(post),
                      onMediaUpdated: _updateMediaPost,
                      onReply: () => showPostComposer(
                        ctx,
                        wallet: widget.wallet,
                        nostrService: widget.nostrService,
                        replyToPost: post,
                        onPublished: (reply) {
                          if (!mounted) return;
                          setState(() => _posts = _mergePosts(_posts, [reply]));
                        },
                      ),
                    ),
                  );
                }, childCount: roots.length),
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
    required this.isFollowing,
    required this.onFollowTap,
  });

  final String pubkey;
  final int postCount;
  final bool isFollowing;
  final VoidCallback onFollowTap;

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
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              _LargeAvatar(pubkeyHex: pubkey),
              const Spacer(),
              Column(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Text('$postCount', style: SpotType.subheading),
                  const SizedBox(height: 2),
                  const Text('Posts', style: SpotType.caption),
                ],
              ),
              const SizedBox(width: SpotSpacing.xl),
            ],
          ),
          const SizedBox(height: SpotSpacing.md),
          Text(_shortKey(pubkey), style: SpotType.mono),
          const SizedBox(height: SpotSpacing.lg),
          SizedBox(
            width: double.infinity,
            child: isFollowing
                ? OutlinedButton(
                    onPressed: onFollowTap,
                    child: const Text('Following'),
                  )
                : FilledButton(
                    onPressed: onFollowTap,
                    child: const Text('Follow'),
                  ),
          ),
        ],
      ),
    );
  }
}

// ── Large avatar ──────────────────────────────────────────────────────────────

class _LargeAvatar extends StatelessWidget {
  const _LargeAvatar({required this.pubkeyHex});

  final String pubkeyHex;

  @override
  Widget build(BuildContext context) {
    final hex = pubkeyHex.length >= 6 ? pubkeyHex.substring(0, 6) : '888480';
    final value = int.tryParse(hex, radix: 16) ?? 0x888480;
    final r = (value >> 16) & 0xFF;
    final g = (value >> 8) & 0xFF;
    final b = value & 0xFF;
    final accent = Color.fromARGB(
      255,
      r.clamp(80, 200),
      g.clamp(80, 180),
      b.clamp(60, 160),
    );

    return Container(
      width: 72,
      height: 72,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: SpotColors.surface,
        border: Border.all(color: accent.withAlpha(120), width: 1),
      ),
      child: Center(
        child: Text(
          pubkeyHex.substring(0, 2).toUpperCase(),
          style: TextStyle(
            color: accent,
            fontSize: 26,
            fontWeight: FontWeight.w300,
            fontFamily: 'monospace',
          ),
        ),
      ),
    );
  }
}

// ── Helpers ───────────────────────────────────────────────────────────────────

String _shortKey(String pubkey) {
  if (pubkey.length <= 12) return pubkey;
  return '${pubkey.substring(0, 6)}…${pubkey.substring(pubkey.length - 4)}';
}
