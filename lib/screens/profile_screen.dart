import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:mobile/features/event/event_repository.dart';
import 'package:mobile/features/nostr/nostr_service.dart';
import 'package:mobile/models/event_model.dart';
import 'package:mobile/models/media_post.dart';
import 'package:mobile/models/wallet_model.dart';
import 'package:mobile/screens/post_composer_screen.dart';
import 'package:mobile/screens/settings_screen.dart';
import 'package:mobile/services/cache_manager.dart';
import 'package:mobile/services/local_post_store.dart';
import 'package:mobile/services/post_merge.dart';
import 'package:mobile/services/post_thread_ordering.dart';
import 'package:mobile/theme/spot_theme.dart';
import 'package:mobile/widgets/post_thread_row.dart';

/// Profile screen — shows identity summary and the user's own posts.
class ProfileScreen extends StatefulWidget {
  const ProfileScreen({
    super.key,
    required this.wallet,
    required this.nostrService,
  });

  final WalletModel wallet;
  final NostrService nostrService;

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  late final EventRepository _repo;
  StreamSubscription<CivicEvent>? _sub;

  List<MediaPost> _posts = [];
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _repo = EventRepository(nostrService: widget.nostrService);
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
      await widget.nostrService.connect();
      _sub = _repo
          .subscribeToAuthorPosts(widget.wallet.publicKeyHex)
          .listen(_onEvent);
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
    if (merged.length == _posts.length) return;
    setState(() => _posts = merged);
  }

  Future<void> _refresh() async {
    await _sub?.cancel();
    _repo.reset();
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

  Future<void> _deletePost(MediaPost post) async {
    // Optimistic removal from UI
    setState(() => _posts = _posts.where((p) => p.id != post.id).toList());
    await LocalPostStore.instance.removePost(post.id);
    try {
      // Publish revocation event (kind-5) with content hash (spec v1.4 §12)
      await widget.nostrService.deletePost(
        post.nostrEventId,
        post.contentHash,
        widget.wallet,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Post deleted. Swarm participants will be notified to remove local copies.',
            ),
          ),
        );
      }
    } catch (e) {
      await LocalPostStore.instance.savePost(post);
      // Restore post on failure
      if (mounted) {
        setState(() {
          _posts = _mergePosts(_posts, [post]);
        });
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Failed to delete post')));
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
      // Also block locally so it disappears from this user's feed
      setState(() => _posts = _posts.where((p) => p.id != post.id).toList());
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Reported. Content hidden.')),
        );
      }
    } catch (_) {}
  }

  void _openSettings() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => SettingsScreen(
          wallet: widget.wallet,
          nostrService: widget.nostrService,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final threadedPosts = buildThreadedPostEntries(_posts);
    return Scaffold(
      backgroundColor: SpotColors.bg,
      appBar: AppBar(
        backgroundColor: SpotColors.bg,
        title: const Text('Profile', style: SpotType.subheading),
        actions: [
          IconButton(
            icon: const Icon(CupertinoIcons.settings, size: 20),
            color: SpotColors.textSecondary,
            tooltip: 'Settings',
            onPressed: _openSettings,
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
            // ── Profile header ─────────────────────────────────────────────
            SliverToBoxAdapter(
              child: _ProfileHeader(
                wallet: widget.wallet,
                postCount: _posts.length,
              ),
            ),

            // ── Divider ────────────────────────────────────────────────────
            const SliverToBoxAdapter(child: Divider(height: 1, thickness: 0.5)),

            // ── Posts ──────────────────────────────────────────────────────
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
            else if (_error != null && _posts.isEmpty)
              SliverFillRemaining(
                child: Center(
                  child: Text(
                    'Could not load posts',
                    style: SpotType.bodySecondary,
                  ),
                ),
              )
            else if (_posts.isEmpty)
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
                ),
              )
            else
              SliverList(
                delegate: SliverChildBuilderDelegate((ctx, i) {
                  final entry = threadedPosts[i];
                  final post = entry.post;
                  return PostThreadRow(
                    post: post,
                    isLast: isLastInThread(threadedPosts, i),
                    onReply: () => showPostComposer(
                      ctx,
                      wallet: widget.wallet,
                      nostrService: widget.nostrService,
                      eventRepo: _repo,
                      replyToPost: post,
                    ),
                    onDelete: () => _deletePost(post),
                    onReport: () => _reportPost(post),
                    onLike: () => _toggleLike(post),
                  );
                }, childCount: threadedPosts.length),
              ),
          ],
        ),
      ),
    );
  }
}

// ── Profile header ─────────────────────────────────────────────────────────────

class _ProfileHeader extends StatelessWidget {
  const _ProfileHeader({required this.wallet, required this.postCount});

  final WalletModel wallet;
  final int postCount;

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
              // Avatar
              _LargeAvatar(pubkeyHex: wallet.publicKeyHex),
              const Spacer(),
              // Post count
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
          // npub
          GestureDetector(
            onTap: () {
              Clipboard.setData(ClipboardData(text: wallet.npub));
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Copied to clipboard')),
              );
            },
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(wallet.npubShort, style: SpotType.mono),
                const SizedBox(width: SpotSpacing.xs),
                const Icon(
                  CupertinoIcons.doc_on_doc,
                  color: SpotColors.textTertiary,
                  size: 11,
                ),
              ],
            ),
          ),
          const SizedBox(height: SpotSpacing.xs),
          // Device
          Text(
            wallet.deviceId.length > 20
                ? '${wallet.deviceId.substring(0, 14)}…'
                : wallet.deviceId,
            style: SpotType.caption,
          ),
        ],
      ),
    );
  }
}

// ── Large avatar ───────────────────────────────────────────────────────────────

class _LargeAvatar extends StatelessWidget {
  const _LargeAvatar({required this.pubkeyHex});

  final String pubkeyHex;

  @override
  Widget build(BuildContext context) {
    final hex = pubkeyHex.length >= 6 ? pubkeyHex.substring(0, 6) : '888480';
    final value = int.tryParse(hex, radix: 16) ?? 0x888480;
    final r = ((value >> 16) & 0xFF);
    final g = ((value >> 8) & 0xFF);
    final b = (value & 0xFF);
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
