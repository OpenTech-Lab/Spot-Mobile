import 'dart:async';

import 'package:flutter/material.dart';

import 'package:mobile/features/event/event_repository.dart';
import 'package:mobile/features/nostr/nostr_service.dart';
import 'package:mobile/models/event_model.dart';
import 'package:mobile/models/media_post.dart';
import 'package:mobile/models/wallet_model.dart';
import 'package:mobile/theme/spot_theme.dart';
import 'package:mobile/widgets/post_thread_row.dart';

/// Shows only the posts authored by the current wallet owner.
class MyPostsScreen extends StatefulWidget {
  const MyPostsScreen({
    super.key,
    required this.wallet,
    required this.nostrService,
  });

  final WalletModel wallet;
  final NostrService nostrService;

  @override
  State<MyPostsScreen> createState() => _MyPostsScreenState();
}

class _MyPostsScreenState extends State<MyPostsScreen> {
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
    final mine = event.posts
        .where((p) => p.pubkey == widget.wallet.publicKeyHex)
        .toList();
    if (mine.isEmpty) return;
    final existingIds = {for (final p in _posts) p.id};
    final incoming = mine.where((p) => !existingIds.contains(p.id)).toList();
    if (incoming.isEmpty) return;
    final merged = [..._posts, ...incoming]
      ..sort((a, b) => b.capturedAt.compareTo(a.capturedAt));
    setState(() => _posts = merged);
  }

  Future<void> _refresh() async {
    await _sub?.cancel();
    setState(() => _posts = []);
    await _initFeed();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: SpotColors.bg,
      appBar: AppBar(
        backgroundColor: SpotColors.bg,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new, size: 16),
          color: SpotColors.textSecondary,
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: const Text('My Posts', style: SpotType.subheading),
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_isLoading && _posts.isEmpty) {
      return const Center(
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
            Text('Loading', style: SpotType.label),
          ],
        ),
      );
    }

    if (_error != null && _posts.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(SpotSpacing.xxxl),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.wifi_off_outlined,
                color: SpotColors.textTertiary,
                size: 32,
              ),
              const SizedBox(height: SpotSpacing.xl),
              const Text(
                'Could not load posts',
                style: SpotType.bodySecondary,
              ),
              const SizedBox(height: SpotSpacing.xl),
              GestureDetector(
                onTap: _refresh,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: SpotSpacing.xl,
                    vertical: SpotSpacing.sm,
                  ),
                  decoration: BoxDecoration(
                    border: Border.all(color: SpotColors.border, width: 0.5),
                    borderRadius: BorderRadius.circular(SpotRadius.sm),
                  ),
                  child: const Text('Retry', style: SpotType.bodySecondary),
                ),
              ),
            ],
          ),
        ),
      );
    }

    if (_posts.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.camera_outlined,
              color: SpotColors.overlay,
              size: 36,
            ),
            const SizedBox(height: SpotSpacing.lg),
            Text(
              'No posts yet',
              style: SpotType.bodySecondary
                  .copyWith(fontWeight: FontWeight.w300),
            ),
            const SizedBox(height: SpotSpacing.xs),
            const Text(
              'Capture a moment to see it here',
              style: SpotType.caption,
            ),
          ],
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
        itemCount: _posts.length,
        itemBuilder: (ctx, i) => PostThreadRow(
          post: _posts[i],
          isLast: i == _posts.length - 1,
        ),
      ),
    );
  }
}
