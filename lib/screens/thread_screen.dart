import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';

import 'package:mobile/features/event/event_repository.dart';
import 'package:mobile/features/nostr/nostr_service.dart';
import 'package:mobile/features/p2p/p2p_service.dart';
import 'package:mobile/models/media_post.dart';
import 'package:mobile/models/wallet_model.dart';
import 'package:mobile/screens/post_composer_screen.dart';
import 'package:mobile/screens/user_profile_screen.dart';
import 'package:mobile/services/local_post_store.dart';
import 'package:mobile/services/media_sync_service.dart';
import 'package:mobile/services/post_merge.dart';
import 'package:mobile/services/post_thread_ordering.dart';
import 'package:mobile/theme/spot_theme.dart';
import 'package:mobile/widgets/post_thread_row.dart';

class ThreadScreen extends StatefulWidget {
  const ThreadScreen({
    super.key,
    required this.rootPostId,
    required this.initialPosts,
    required this.wallet,
    required this.nostrService,
    this.eventRepo,
    this.mediaFetcher,
  });

  final String rootPostId;
  final List<MediaPost> initialPosts;
  final WalletModel wallet;
  final NostrService nostrService;
  final EventRepository? eventRepo;
  final MediaFetcher? mediaFetcher;

  @override
  State<ThreadScreen> createState() => _ThreadScreenState();
}

class _ThreadScreenState extends State<ThreadScreen> {
  late List<MediaPost> _posts;
  final Set<String> _loadingMediaPostIds = {};

  @override
  void initState() {
    super.initState();
    _posts = List<MediaPost>.from(widget.initialPosts);
    unawaited(_syncThreadMedia());
  }

  List<ThreadedPostEntry> get _entries =>
      threadEntriesForRoot(_posts, widget.rootPostId);

  MediaPost? get _rootPost {
    for (final post in _posts) {
      if (post.nostrEventId == widget.rootPostId) return post;
    }
    return null;
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

  Future<void> _reportPost(MediaPost post) async {
    try {
      await widget.nostrService.reportContent(
        eventId: post.nostrEventId,
        contentHash: post.contentHash,
        reason: 'harmful',
        wallet: widget.wallet,
      );
      if (!mounted) return;
      setState(() {
        _posts = _posts.where((candidate) => candidate.id != post.id).toList();
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Reported. Content hidden.')),
      );
    } catch (_) {}
  }

  void _mergePost(MediaPost post) {
    setState(() => _posts = mergePostsPreservingLocalState(_posts, [post]));
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

  bool _needsMediaHydration(MediaPost post) {
    if (post.isTextOnly || post.contentHashes.isEmpty) return false;
    for (var i = 0; i < post.contentHashes.length; i++) {
      if (i >= post.mediaPaths.length ||
          !File(post.mediaPaths[i]).existsSync()) {
        return true;
      }
    }
    return false;
  }

  Future<void> _syncThreadMedia() async {
    await P2PService.instance.startSwarm();
    final sync = MediaSyncService(
      fetchMedia: widget.mediaFetcher ?? P2PService.instance.requestMedia,
    );
    final candidates = _entries
        .map((entry) => entry.post)
        .where(_needsMediaHydration)
        .toList(growable: false);
    if (!mounted || candidates.isEmpty) return;

    setState(() {
      _loadingMediaPostIds.addAll(candidates.map((post) => post.id));
    });

    for (final post in candidates) {
      final hydrated = await sync.hydratePost(post);
      if (!mounted) return;

      if (hydrated.mediaPaths.length != post.mediaPaths.length ||
          !_samePaths(hydrated.mediaPaths, post.mediaPaths)) {
        _updateMediaPost(hydrated);
      } else {
        setState(() => _loadingMediaPostIds.remove(post.id));
      }
    }
  }

  bool _samePaths(List<String> left, List<String> right) {
    if (left.length != right.length) return false;
    for (var i = 0; i < left.length; i++) {
      if (left[i] != right[i]) return false;
    }
    return true;
  }

  @override
  Widget build(BuildContext context) {
    final entries = _entries;
    final rootPost = _rootPost;
    final categoryTag = rootPost?.eventTags.isNotEmpty == true
        ? rootPost!.eventTags.first
        : null;
    final title = categoryTag != null ? '#$categoryTag' : 'Thread';

    return Scaffold(
      backgroundColor: SpotColors.bg,
      appBar: AppBar(
        backgroundColor: SpotColors.bg,
        title: Text(title, style: SpotType.subheading),
      ),
      body: entries.isEmpty
          ? const Center(
              child: Text(
                'Thread not available',
                style: SpotType.bodySecondary,
              ),
            )
          : ListView.builder(
              padding: const EdgeInsets.only(
                top: SpotSpacing.sm,
                bottom: SpotSpacing.xl,
              ),
              itemCount: entries.length,
              itemBuilder: (ctx, i) {
                final post = entries[i].post;
                return PostThreadRow(
                  post: post,
                  isLast: i == entries.length - 1,
                  isMediaLoading: _loadingMediaPostIds.contains(post.id),
                  onAvatarTap: () => _openUserProfile(ctx, post.pubkey),
                  onReport: () => _reportPost(post),
                  onLike: () => _toggleLike(post),
                  onMediaUpdated: _updateMediaPost,
                  onReply: () => showPostComposer(
                    ctx,
                    wallet: widget.wallet,
                    nostrService: widget.nostrService,
                    eventRepo: widget.eventRepo,
                    replyToPost: post,
                    onPublished: _mergePost,
                  ),
                );
              },
            ),
    );
  }
}
