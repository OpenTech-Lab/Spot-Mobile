import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'package:mobile/features/event/event_repository.dart';
import 'package:mobile/features/event/event_screen.dart';
import 'package:mobile/features/nostr/nostr_service.dart';
import 'package:mobile/models/event_model.dart';

/// Main content feed — subscribes to Nostr relays and shows live [CivicEvent]s.
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
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      await widget.nostrService.connect();
      _sub = _repo.subscribeToEvents().listen((event) {
        if (mounted) {
          setState(() {
            // Upsert by hashtag
            final idx =
                _events.indexWhere((e) => e.hashtag == event.hashtag);
            if (idx == -1) {
              _events = [event, ..._events];
            } else {
              final updated = List<CivicEvent>.from(_events);
              updated[idx] = event;
              _events = updated;
            }
            // Sort newest first
            _events.sort(
                (a, b) => b.firstSeen.compareTo(a.firstSeen));
          });
        }
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
      backgroundColor: const Color(0xFF0D0D0D),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0D0D0D),
        title: const Text(
          'SPOT',
          style: TextStyle(
            color: Color(0xFFFF4444),
            fontWeight: FontWeight.bold,
            letterSpacing: 4,
            fontFamily: 'monospace',
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh, color: Colors.white54),
            onPressed: _refresh,
            tooltip: 'Refresh',
          ),
        ],
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_isLoading && _events.isEmpty) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(color: Color(0xFFFF4444)),
            SizedBox(height: 16),
            Text('Connecting to relays...',
                style: TextStyle(color: Colors.white54)),
          ],
        ),
      );
    }

    if (_error != null && _events.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.wifi_off, color: Colors.white30, size: 48),
              const SizedBox(height: 16),
              Text('Connection failed: $_error',
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white54)),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: _refresh,
                style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFFFF4444)),
                child: const Text('Retry'),
              ),
            ],
          ),
        ),
      );
    }

    if (_events.isEmpty) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.inbox, color: Colors.white24, size: 56),
            SizedBox(height: 16),
            Text('No events yet.',
                style: TextStyle(color: Colors.white54, fontSize: 16)),
            SizedBox(height: 8),
            Text('Be the first to post!',
                style: TextStyle(color: Colors.white30)),
          ],
        ),
      );
    }

    return RefreshIndicator(
      color: const Color(0xFFFF4444),
      backgroundColor: const Color(0xFF1A1A1A),
      onRefresh: _refresh,
      child: ListView.builder(
        padding: const EdgeInsets.only(top: 8),
        itemCount: _events.length,
        itemBuilder: (ctx, i) => _FeedCard(
          event: _events[i],
          onTap: () => Navigator.of(ctx).push(
            MaterialPageRoute(
              builder: (_) => EventScreen(event: _events[i]),
            ),
          ),
        ),
      ),
    );
  }
}

// ── Feed card ─────────────────────────────────────────────────────────────────

class _FeedCard extends StatelessWidget {
  const _FeedCard({required this.event, required this.onTap});

  final CivicEvent event;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final df = DateFormat('MMM d · HH:mm');
    final latest = event.latestPost;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: const Color(0xFF1A1A1A),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFF2A2A2A)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Thumbnail placeholder
            Container(
              height: 160,
              decoration: BoxDecoration(
                color: const Color(0xFF0D0D0D),
                borderRadius:
                    const BorderRadius.vertical(top: Radius.circular(12)),
              ),
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      latest?.isDangerMode ?? false
                          ? Icons.shield
                          : Icons.photo_camera,
                      color: latest?.isDangerMode ?? false
                          ? const Color(0xFFFF4444)
                          : Colors.white24,
                      size: 40,
                    ),
                    if (latest?.isDangerMode ?? false)
                      const Padding(
                        padding: EdgeInsets.only(top: 6),
                        child: Text(
                          'DANGER MODE',
                          style: TextStyle(
                            color: Color(0xFFFF4444),
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),

            Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Hashtag
                  Text(
                    '#${event.hashtag}',
                    style: const TextStyle(
                      color: Color(0xFFFF4444),
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      // GPS badge
                      if (event.centerLat != null)
                        _Badge(
                          icon: Icons.location_on,
                          label:
                              '${event.centerLat!.toStringAsFixed(2)}, ${event.centerLon!.toStringAsFixed(2)}',
                          color: Colors.greenAccent,
                        )
                      else
                        const _Badge(
                          icon: Icons.location_off,
                          label: 'GPS hidden',
                          color: Colors.white38,
                        ),
                      const SizedBox(width: 8),
                      // Post count
                      _Badge(
                        icon: Icons.image,
                        label: '${event.posts.length}',
                        color: Colors.white54,
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        '${event.participantCount} contributor${event.participantCount == 1 ? '' : 's'}',
                        style: const TextStyle(
                            color: Colors.white54, fontSize: 12),
                      ),
                      Text(
                        df.format(event.firstSeen.toLocal()),
                        style: const TextStyle(
                            color: Colors.white38, fontSize: 11),
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

class _Badge extends StatelessWidget {
  const _Badge(
      {required this.icon, required this.label, required this.color});

  final IconData icon;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, color: color, size: 12),
        const SizedBox(width: 3),
        Text(label, style: TextStyle(color: color, fontSize: 11)),
      ],
    );
  }
}
