import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'package:mobile/models/event_model.dart';
import 'package:mobile/models/media_post.dart';

/// Event detail screen — shows a [CivicEvent] as a wiki-like live timeline.
///
/// Navigated to with a [CivicEvent] argument:
/// ```dart
/// Navigator.of(context).push(MaterialPageRoute(
///   builder: (_) => EventScreen(event: myEvent),
/// ));
/// ```
class EventScreen extends StatelessWidget {
  const EventScreen({super.key, required this.event});

  final CivicEvent event;

  @override
  Widget build(BuildContext context) {
    final posts = event.postsByNewest;

    return Scaffold(
      backgroundColor: const Color(0xFF0D0D0D),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0D0D0D),
        foregroundColor: Colors.white,
        title: Text(
          '#${event.hashtag}',
          style: const TextStyle(
            fontFamily: 'monospace',
            color: Color(0xFFFF4444),
            fontWeight: FontWeight.bold,
          ),
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Chip(
              backgroundColor: const Color(0xFF1A1A1A),
              label: Text(
                '${event.participantCount} contributors',
                style: const TextStyle(
                    color: Colors.white70, fontSize: 11),
              ),
            ),
          ),
        ],
      ),
      body: CustomScrollView(
        slivers: [
          // ── Event header ──────────────────────────────────────────────────
          SliverToBoxAdapter(
            child: _EventHeader(event: event),
          ),

          // ── Post count separator ──────────────────────────────────────────
          SliverToBoxAdapter(
            child: Padding(
              padding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                children: [
                  const Icon(Icons.photo_library,
                      color: Color(0xFFFF4444), size: 16),
                  const SizedBox(width: 6),
                  Text(
                    '${posts.length} posts',
                    style: const TextStyle(
                        color: Colors.white70, fontSize: 13),
                  ),
                ],
              ),
            ),
          ),

          // ── Timeline list ─────────────────────────────────────────────────
          posts.isEmpty
              ? const SliverFillRemaining(
                  child: Center(
                    child: Text(
                      'No posts yet.',
                      style: TextStyle(color: Colors.white54),
                    ),
                  ),
                )
              : SliverList(
                  delegate: SliverChildBuilderDelegate(
                    (ctx, i) => _PostCard(post: posts[i]),
                    childCount: posts.length,
                  ),
                ),
        ],
      ),
    );
  }
}

// ── Event header ──────────────────────────────────────────────────────────────

class _EventHeader extends StatelessWidget {
  const _EventHeader({required this.event});

  final CivicEvent event;

  @override
  Widget build(BuildContext context) {
    final df = DateFormat('MMM d, yyyy HH:mm');

    return Container(
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A1A),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF2A2A2A)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            event.title,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 20,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          _StatRow(
              icon: Icons.access_time,
              label: 'First seen',
              value: df.format(event.firstSeen.toLocal())),
          const SizedBox(height: 4),
          _StatRow(
              icon: Icons.people,
              label: 'Participants',
              value: event.participantCount.toString()),
          if (event.centerLat != null && event.centerLon != null) ...[
            const SizedBox(height: 4),
            _StatRow(
              icon: Icons.location_on,
              label: 'Centre',
              value:
                  '${event.centerLat!.toStringAsFixed(4)}, ${event.centerLon!.toStringAsFixed(4)}',
            ),
          ],
          if (event.centerLat == null) ...[
            const SizedBox(height: 4),
            const _StatRow(
                icon: Icons.location_off,
                label: 'Location',
                value: 'GPS hidden (Danger Mode)'),
          ],
          const SizedBox(height: 12),
          // Map placeholder
          Container(
            height: 120,
            decoration: BoxDecoration(
              color: const Color(0xFF0D0D0D),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: const Color(0xFF3A3A3A)),
            ),
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.map, color: Color(0xFFFF4444), size: 32),
                  const SizedBox(height: 4),
                  Text(
                    event.centerLat != null
                        ? '${event.centerLat!.toStringAsFixed(4)}, ${event.centerLon!.toStringAsFixed(4)}'
                        : 'Location hidden',
                    style: const TextStyle(
                        color: Colors.white54, fontSize: 11),
                  ),
                  const SizedBox(height: 2),
                  const Text(
                    'Map — TODO: integrate Leaflet/flutter_map',
                    style: TextStyle(color: Colors.white30, fontSize: 10),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _StatRow extends StatelessWidget {
  const _StatRow(
      {required this.icon, required this.label, required this.value});

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, color: Colors.white38, size: 14),
        const SizedBox(width: 6),
        Text('$label: ',
            style:
                const TextStyle(color: Colors.white54, fontSize: 12)),
        Expanded(
          child: Text(value,
              style: const TextStyle(
                  color: Colors.white70, fontSize: 12),
              overflow: TextOverflow.ellipsis),
        ),
      ],
    );
  }
}

// ── Post card ─────────────────────────────────────────────────────────────────

class _PostCard extends StatelessWidget {
  const _PostCard({required this.post});

  final MediaPost post;

  @override
  Widget build(BuildContext context) {
    final df = DateFormat('MMM d HH:mm');
    final shortPubkey =
        post.pubkey.length > 16 ? '${post.pubkey.substring(0, 8)}...' : post.pubkey;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A1A),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: post.isDangerMode
              ? const Color(0xFFFF4444).withOpacity(0.5)
              : const Color(0xFF2A2A2A),
        ),
      ),
      child: Row(
        children: [
          // Thumbnail placeholder
          Container(
            width: 80,
            height: 80,
            decoration: BoxDecoration(
              color: const Color(0xFF0D0D0D),
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(10),
                bottomLeft: Radius.circular(10),
              ),
            ),
            child: Icon(
              post.isDangerMode ? Icons.shield : Icons.image,
              color: post.isDangerMode
                  ? const Color(0xFFFF4444)
                  : Colors.white30,
              size: 32,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Danger badge
                  if (post.isDangerMode)
                    Container(
                      margin: const EdgeInsets.only(bottom: 4),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFF4444),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: const Text(
                        'DANGER MODE',
                        style: TextStyle(
                            color: Colors.white,
                            fontSize: 9,
                            fontWeight: FontWeight.bold),
                      ),
                    ),
                  // Author
                  Text(
                    shortPubkey,
                    style: const TextStyle(
                        color: Color(0xFFFF4444),
                        fontSize: 11,
                        fontFamily: 'monospace'),
                  ),
                  const SizedBox(height: 2),
                  // Time
                  Text(
                    df.format(post.capturedAt.toLocal()),
                    style: const TextStyle(
                        color: Colors.white54, fontSize: 11),
                  ),
                  const SizedBox(height: 4),
                  // GPS badge
                  Row(
                    children: [
                      Icon(
                        post.hasGps ? Icons.gps_fixed : Icons.gps_off,
                        color: post.hasGps
                            ? Colors.greenAccent
                            : Colors.white30,
                        size: 12,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        post.hasGps
                            ? '${post.latitude!.toStringAsFixed(3)}, ${post.longitude!.toStringAsFixed(3)}'
                            : 'GPS hidden',
                        style: const TextStyle(
                            color: Colors.white38, fontSize: 11),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const Icon(Icons.chevron_right, color: Colors.white30),
          const SizedBox(width: 8),
        ],
      ),
    );
  }
}
