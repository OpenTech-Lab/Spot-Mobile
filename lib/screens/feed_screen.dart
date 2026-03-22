import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import 'package:mobile/features/event/event_repository.dart';
import 'package:mobile/features/nostr/nostr_service.dart';
import 'package:mobile/models/event_model.dart';
import 'package:mobile/models/media_post.dart';
import 'package:mobile/theme/spot_theme.dart';
import 'package:mobile/widgets/post_thread_row.dart';

/// Main content feed — chronological thread of [MediaPost]s from Nostr relays.
class FeedScreen extends StatefulWidget {
  const FeedScreen({super.key, required this.nostrService});

  final NostrService nostrService;

  @override
  State<FeedScreen> createState() => _FeedScreenState();
}

class _FeedScreenState extends State<FeedScreen> {
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
    final existingIds = {for (final p in _posts) p.id};
    final incoming =
        event.posts.where((p) => !existingIds.contains(p.id)).toList();
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
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: SpotColors.bg,
        body: _buildBody(),
      );

  Widget _buildBody() {
    if (_isLoading && _posts.isEmpty) return _buildLoading();
    if (_error != null && _posts.isEmpty) return _buildError();
    if (_posts.isEmpty) return _buildEmpty();

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

  Widget _buildError() => Center(
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

  Widget _buildEmpty() => Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              CupertinoIcons.tray,
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
            const Text('Be the first to record', style: SpotType.caption),
          ],
        ),
      );
}
