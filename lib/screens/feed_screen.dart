import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'package:mobile/features/event/event_repository.dart';
import 'package:mobile/features/event/event_screen.dart';
import 'package:mobile/features/nostr/nostr_service.dart';
import 'package:mobile/models/event_model.dart';
import 'package:mobile/theme/spot_theme.dart';

/// Main content feed — live [CivicEvent] stream from Nostr relays.
class FeedScreen extends StatefulWidget {
  const FeedScreen({super.key, required this.nostrService});

  final NostrService nostrService;

  @override
  State<FeedScreen> createState() => _FeedScreenState();
}

class _FeedScreenState extends State<FeedScreen> {
  late final EventRepository _repo;
  StreamSubscription<CivicEvent>? _sub;

  List<CivicEvent> _events = [];
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
    setState(() { _isLoading = true; _error = null; });
    try {
      await widget.nostrService.connect();
      _sub = _repo.subscribeToEvents().listen((event) {
        if (!mounted) return;
        setState(() {
          final idx = _events.indexWhere((e) => e.hashtag == event.hashtag);
          if (idx == -1) {
            _events = [event, ..._events];
          } else {
            final updated = List<CivicEvent>.from(_events);
            updated[idx] = event;
            _events = updated;
          }
          _events.sort((a, b) => b.firstSeen.compareTo(a.firstSeen));
        });
      });
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _refresh() async {
    await _sub?.cancel();
    _events = [];
    await _initFeed();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: SpotColors.bg,
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_isLoading && _events.isEmpty) {
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
            Text('Connecting', style: SpotType.label),
          ],
        ),
      );
    }

    if (_error != null && _events.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(SpotSpacing.xxxl),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.wifi_off_outlined, color: SpotColors.textTertiary, size: 32),
              const SizedBox(height: SpotSpacing.xl),
              const Text('Could not connect to relays', style: SpotType.bodySecondary),
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

    if (_events.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.inbox_outlined, color: SpotColors.overlay, size: 36),
            const SizedBox(height: SpotSpacing.lg),
            Text(
              'No posts yet',
              style: SpotType.bodySecondary.copyWith(fontWeight: FontWeight.w300),
            ),
            const SizedBox(height: SpotSpacing.xs),
            const Text('Be the first to record', style: SpotType.caption),
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
          top: SpotSpacing.md,
          bottom: SpotSpacing.xl,
        ),
        itemCount: _events.length,
        itemBuilder: (ctx, i) => _FeedCard(
          event: _events[i],
          onTap: () => Navigator.of(ctx).push(
            MaterialPageRoute(builder: (_) => EventScreen(event: _events[i])),
          ),
        ),
      ),
    );
  }
}

// ── Feed card ──────────────────────────────────────────────────────────────────

class _FeedCard extends StatelessWidget {
  const _FeedCard({required this.event, required this.onTap});

  final CivicEvent event;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final df = DateFormat('MMM d · HH:mm');
    final latest = event.latestPost;
    final isDanger = latest?.isDangerMode ?? false;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.symmetric(
          horizontal: SpotSpacing.lg,
          vertical: 4,
        ),
        decoration: SpotDecoration.card(radius: SpotRadius.sm),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Media placeholder area
            Container(
              height: 144,
              decoration: BoxDecoration(
                color: SpotColors.bg,
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(SpotRadius.sm),
                ),
              ),
              child: Center(
                child: isDanger
                    ? Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.shield_outlined,
                            color: SpotColors.danger.withAlpha(140),
                            size: 24,
                          ),
                          const SizedBox(height: SpotSpacing.sm),
                          Text(
                            'Protected',
                            style: SpotType.label.copyWith(
                              color: SpotColors.danger.withAlpha(140),
                            ),
                          ),
                        ],
                      )
                    : const Icon(
                        Icons.photo_camera_outlined,
                        color: SpotColors.overlay,
                        size: 24,
                      ),
              ),
            ),

            // Info row
            Padding(
              padding: const EdgeInsets.fromLTRB(
                SpotSpacing.lg,
                SpotSpacing.md,
                SpotSpacing.lg,
                SpotSpacing.lg,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('#${event.hashtag}', style: SpotType.body),
                  const SizedBox(height: SpotSpacing.sm),
                  Wrap(
                    spacing: SpotSpacing.xs,
                    runSpacing: SpotSpacing.xs,
                    children: [
                      _Tag(
                        event.centerLat != null
                            ? '${event.centerLat!.toStringAsFixed(2)}, '
                                '${event.centerLon!.toStringAsFixed(2)}'
                            : 'Location hidden',
                      ),
                      _Tag('${event.posts.length} posts'),
                    ],
                  ),
                  const SizedBox(height: SpotSpacing.sm),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        '${event.participantCount} '
                        'contributor${event.participantCount == 1 ? '' : 's'}',
                        style: SpotType.caption,
                      ),
                      Text(
                        df.format(event.firstSeen.toLocal()),
                        style: SpotType.caption,
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Tag extends StatelessWidget {
  const _Tag(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: SpotSpacing.sm,
        vertical: 3,
      ),
      decoration: BoxDecoration(
        color: SpotColors.surfaceHigh,
        borderRadius: BorderRadius.circular(SpotRadius.xs),
      ),
      child: Text(label, style: SpotType.caption),
    );
  }
}
