import 'dart:async';
import 'dart:io';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';

import 'package:mobile/core/encryption.dart';
import 'package:mobile/core/wallet.dart';
import 'package:mobile/features/event/event_repository.dart';
import 'package:mobile/features/metadata/metadata_service.dart';
import 'package:mobile/models/event_model.dart';
import 'package:mobile/models/media_post.dart';
import 'package:mobile/models/profile_model.dart';
import 'package:mobile/models/wallet_model.dart';
import 'package:mobile/screens/discover_screen.dart';
import 'package:mobile/screens/post_composer_screen.dart';
import 'package:mobile/screens/settings_screen.dart';
import 'package:mobile/screens/thread_screen.dart';
import 'package:mobile/services/cache_manager.dart';
import 'package:mobile/services/cdn_media_service.dart';
import 'package:mobile/services/local_post_store.dart';
import 'package:mobile/services/media_processing_service.dart';
import 'package:mobile/services/post_publish_service.dart';
import 'package:mobile/services/post_merge.dart';
import 'package:mobile/services/post_thread_ordering.dart';
import 'package:mobile/theme/spot_theme.dart';
import 'package:mobile/widgets/profile_avatar.dart';
import 'package:mobile/widgets/post_thread_row.dart';

/// Profile screen — shows identity summary and the user's own posts.
class ProfileScreen extends StatefulWidget {
  const ProfileScreen({
    super.key,
    required this.wallet,
    required this.eventRepo,
  });

  final WalletModel wallet;
  final EventRepository eventRepo;

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  EventRepository get _repo => widget.eventRepo;
  StreamSubscription<CivicEvent>? _sub;
  StreamSubscription<List<MediaPost>>? _localSub;

  List<MediaPost> _posts = [];
  bool _isLoading = true;
  String? _error;
  final Set<String> _retryingPostIds = {};
  ProfileModel? _profile;
  bool _isSavingProfile = false;

  @override
  void initState() {
    super.initState();
    _initFeed();
  }

  @override
  void dispose() {
    _sub?.cancel();
    _localSub?.cancel();
    super.dispose();
  }

  Future<void> _initFeed() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      _localSub ??= LocalPostStore.instance.changes.listen(
        _onLocalPostsChanged,
      );
      await _loadPersistedPosts();
      await _loadProfile();
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
    if (orderedPostsEqual(merged, _posts)) return;
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
      includeFailedToSend: true,
    );
    final visible = _visiblePersistedPosts(persisted);
    if (!mounted) return;
    setState(() => _posts = _mergePersistedPosts(visible));
  }

  Future<void> _loadProfile() async {
    try {
      final profile = await MetadataService.instance.fetchCurrentProfile(
        widget.wallet,
      );
      if (!mounted) return;
      setState(() => _profile = profile);
    } catch (e) {
      debugPrint('[ProfileScreen] Failed to load profile: $e');
    }
  }

  List<MediaPost> _mergePosts(
    List<MediaPost> current,
    Iterable<MediaPost> incoming,
  ) => mergePostsPreservingLocalState(current, incoming);

  List<MediaPost> _visiblePersistedPosts(Iterable<MediaPost> posts) {
    return posts
        .where(
          (post) =>
              post.pubkey == widget.wallet.publicKeyHex &&
              post.contentHashes.every(
                (hash) => !CacheManager.instance.isBlocked(hash),
              ),
        )
        .toList();
  }

  List<MediaPost> _mergePersistedPosts(Iterable<MediaPost> persisted) {
    final nonPending = _posts.where((post) => !post.isPendingRetry).toList();
    return _mergePosts(nonPending, persisted);
  }

  void _onLocalPostsChanged(List<MediaPost> persisted) {
    if (!mounted) return;
    final merged = _mergePersistedPosts(_visiblePersistedPosts(persisted));
    if (orderedPostsEqual(merged, _posts)) return;
    setState(() => _posts = merged);
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

  Future<void> _deletePost(MediaPost post) async {
    // Optimistic removal from UI
    setState(() => _posts = _posts.where((p) => p.id != post.id).toList());
    await LocalPostStore.instance.removePost(post.id);
    if (post.isPendingRetry) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Removed local unsent post')),
        );
      }
      return;
    }
    try {
      await MetadataService.instance.deletePost(
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

  Future<void> _retryPost(MediaPost post) async {
    if (_retryingPostIds.contains(post.id)) return;
    setState(() => _retryingPostIds.add(post.id));
    try {
      final published = await PostPublishService.instance.publishDraft(
        draft: post,
        wallet: widget.wallet,
        eventRepo: _repo,
        replaceLocalPostId: post.id,
      );
      if (!mounted) return;
      final withoutOld = _posts.where((item) => item.id != post.id).toList();
      setState(() {
        _retryingPostIds.remove(post.id);
        _posts = _mergePosts(withoutOld, [published]);
      });
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Post sent')));
    } catch (e) {
      final failed = await PostPublishService.instance.saveFailedPublish(
        post,
        e,
      );
      if (!mounted) return;
      setState(() {
        _retryingPostIds.remove(post.id);
        _posts = replacePostsById(_posts, [failed]);
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Retry failed. The post is still saved locally.'),
        ),
      );
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
      MaterialPageRoute(builder: (_) => SettingsScreen(wallet: widget.wallet)),
    );
  }

  void _openDiscoverTag(BuildContext ctx, String tag) {
    Navigator.of(ctx).push(
      buildDiscoverScreenRoute(
        wallet: widget.wallet,
        initialSearchQuery: '#$tag',
      ),
    );
  }

  Future<void> _editProfile() async {
    final nameController = TextEditingController(
      text: _profile?.displayName ?? '',
    );
    final picker = ImagePicker();
    XFile? selectedAvatar;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: SpotColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(SpotRadius.xl),
        ),
      ),
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (sheetContext, setSheetState) {
            return Padding(
              padding: EdgeInsets.only(
                left: SpotSpacing.lg,
                right: SpotSpacing.lg,
                top: SpotSpacing.lg,
                bottom:
                    MediaQuery.of(sheetContext).viewInsets.bottom +
                    SpotSpacing.xl,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Edit Profile', style: SpotType.subheading),
                  const SizedBox(height: SpotSpacing.lg),
                  Center(
                    child: GestureDetector(
                      onTap: _isSavingProfile
                          ? null
                          : () async {
                              final picked = await picker.pickImage(
                                source: ImageSource.gallery,
                                imageQuality: 88,
                                maxWidth: 1200,
                                maxHeight: 1200,
                              );
                              if (picked == null) return;
                              setSheetState(() => selectedAvatar = picked);
                            },
                      child: selectedAvatar != null
                          ? Container(
                              width: 84,
                              height: 84,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                image: DecorationImage(
                                  image: FileImage(File(selectedAvatar!.path)),
                                  fit: BoxFit.cover,
                                ),
                              ),
                            )
                          : ProfileAvatar(
                              pubkey: widget.wallet.publicKeyHex,
                              avatarContentHash: _profile?.avatarContentHash,
                              size: 84,
                            ),
                    ),
                  ),
                  const SizedBox(height: SpotSpacing.sm),
                  Center(
                    child: Text(
                      'Tap avatar to choose a new image',
                      style: SpotType.caption,
                    ),
                  ),
                  const SizedBox(height: SpotSpacing.lg),
                  TextField(
                    controller: nameController,
                    enabled: !_isSavingProfile,
                    maxLength: 32,
                    decoration: const InputDecoration(
                      labelText: 'Username',
                      hintText: 'Citizen name',
                    ),
                  ),
                  const SizedBox(height: SpotSpacing.lg),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: _isSavingProfile
                          ? null
                          : () async {
                              Navigator.of(sheetContext).pop();
                              await _saveProfile(
                                displayName: nameController.text,
                                selectedAvatar: selectedAvatar,
                              );
                            },
                      child: Text(
                        _isSavingProfile ? 'Saving…' : 'Save Profile',
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _saveProfile({
    required String displayName,
    XFile? selectedAvatar,
  }) async {
    setState(() => _isSavingProfile = true);
    try {
      String? avatarContentHash = _profile?.avatarContentHash;
      if (selectedAvatar != null) {
        final optimized = await MediaProcessingService.instance
            .optimizeForUpload(File(selectedAvatar.path), isVideo: false);
        final bytes = await optimized.readAsBytes();
        avatarContentHash = EncryptionUtils.sha256BytesHex(
          Uint8List.fromList(bytes),
        );

        await CacheManager.instance.addToCache(
          avatarContentHash,
          optimized.path,
        );
        await CdnMediaService.instance.ensureUploadedToCdn(
          contentHash: avatarContentHash,
          filePath: optimized.path,
          contentType: _profileImageContentType(
            optimized.path,
            mimeType: selectedAvatar.mimeType,
          ),
          signPayload: (message) async => PresignAuth(
            pubkey: widget.wallet.publicKeyHex,
            signature: WalletService.signMessage(
              message,
              widget.wallet.privateKeyHex,
            ),
          ),
        );
      }

      final updatedProfile = await MetadataService.instance
          .updateCurrentProfile(
            wallet: widget.wallet,
            displayName: displayName,
            avatarContentHash: avatarContentHash,
          );
      if (!mounted) return;
      setState(() => _profile = updatedProfile);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Profile updated')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Failed to update profile: $e')));
    } finally {
      if (mounted) setState(() => _isSavingProfile = false);
    }
  }

  String _profileImageContentType(String path, {String? mimeType}) {
    if (mimeType?.startsWith('image/') == true) return mimeType!;
    final lower = path.toLowerCase();
    if (lower.endsWith('.png')) return 'image/png';
    if (lower.endsWith('.webp')) return 'image/webp';
    return 'image/jpeg';
  }

  @override
  Widget build(BuildContext context) {
    final roots = topLevelThreadPosts(_posts);
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
                profile: _profile,
                onEdit: _editProfile,
                isSavingProfile: _isSavingProfile,
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
                  final post = roots[i];
                  return InkWell(
                    onTap: post.isPendingRetry
                        ? null
                        : () => Navigator.of(ctx).push(
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
                      onTagTap: (tag) => _openDiscoverTag(ctx, tag),
                      onMediaUpdated: _updateMediaPost,
                      onReply: post.isPendingRetry
                          ? null
                          : () => showPostComposer(
                              ctx,
                              wallet: widget.wallet,
                              eventRepo: _repo,
                              replyToPost: post,
                            ),
                      onDelete: () => _deletePost(post),
                      onReport: () => _reportPost(post),
                      onLike: post.isPendingRetry
                          ? null
                          : () => _toggleLike(post),
                      onRetryPublish: post.isPendingRetry
                          ? () => _retryPost(post)
                          : null,
                      isRetrying: _retryingPostIds.contains(post.id),
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

// ── Profile header ─────────────────────────────────────────────────────────────

class _ProfileHeader extends StatelessWidget {
  const _ProfileHeader({
    required this.wallet,
    required this.postCount,
    required this.profile,
    required this.onEdit,
    required this.isSavingProfile,
  });

  final WalletModel wallet;
  final int postCount;
  final ProfileModel? profile;
  final VoidCallback onEdit;
  final bool isSavingProfile;

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
              GestureDetector(
                onTap: isSavingProfile ? null : onEdit,
                child: ProfileAvatar(
                  pubkey: wallet.publicKeyHex,
                  avatarContentHash: profile?.avatarContentHash,
                  size: 72,
                ),
              ),
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
          Text(
            profile?.displayName?.trim().isNotEmpty == true
                ? profile!.displayName!.trim()
                : 'citizen-${wallet.publicKeyHex.substring(0, 8)}',
            style: SpotType.subheading,
          ),
          const SizedBox(height: SpotSpacing.xs),
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
          const SizedBox(height: SpotSpacing.lg),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton(
              onPressed: isSavingProfile ? null : onEdit,
              child: Text(isSavingProfile ? 'Saving…' : 'Edit Profile'),
            ),
          ),
        ],
      ),
    );
  }
}
