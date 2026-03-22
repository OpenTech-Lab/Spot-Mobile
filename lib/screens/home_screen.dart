import 'package:flutter/material.dart';

import 'package:mobile/features/camera/camera_screen.dart';
import 'package:mobile/features/event/event_repository.dart';
import 'package:mobile/features/event/event_screen.dart';
import 'package:mobile/features/nostr/nostr_service.dart';
import 'package:mobile/models/wallet_model.dart';
import 'package:mobile/screens/feed_screen.dart';
import 'package:mobile/screens/wallet_screen.dart';

/// Main app shell with bottom navigation.
///
/// Tab layout:
///   0 — Feed
///   1 — Camera (prominent center button)
///   2 — Events list
///   3 — Wallet / Identity
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key, required this.wallet});

  final WalletModel wallet;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _selectedTab = 0;
  bool _isDangerModeGlobal = false;

  late final NostrService _nostrService;
  late final EventRepository _eventRepo;

  @override
  void initState() {
    super.initState();
    _nostrService = NostrService();
    _eventRepo = EventRepository(nostrService: _nostrService);
    _nostrService.connect();
  }

  @override
  void dispose() {
    _eventRepo.dispose();
    _nostrService.disconnect();
    super.dispose();
  }

  // ── Tab screens ───────────────────────────────────────────────────────────

  Widget _buildCurrentTab() {
    switch (_selectedTab) {
      case 0:
        return FeedScreen(nostrService: _nostrService);
      case 1:
        return CameraScreen(
          wallet: widget.wallet,
          nostrService: _nostrService,
        );
      case 2:
        return _EventsListTab(
          eventRepo: _eventRepo,
          nostrService: _nostrService,
        );
      case 3:
        return WalletScreen(wallet: widget.wallet);
      default:
        return FeedScreen(nostrService: _nostrService);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0D0D0D),
      appBar: _selectedTab == 1
          ? null // Camera screen is full-screen
          : AppBar(
              backgroundColor: const Color(0xFF0D0D0D),
              elevation: 0,
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
                if (_isDangerModeGlobal)
                  Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 8),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFF4444),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.shield,
                              color: Colors.white, size: 14),
                          SizedBox(width: 4),
                          Text(
                            'DANGER',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
      body: _buildCurrentTab(),
      bottomNavigationBar: _buildBottomNav(),
    );
  }

  Widget _buildBottomNav() {
    return Container(
      decoration: const BoxDecoration(
        color: Color(0xFF111111),
        border: Border(top: BorderSide(color: Color(0xFF2A2A2A))),
      ),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _NavItem(
                icon: Icons.feed,
                label: 'Feed',
                selected: _selectedTab == 0,
                onTap: () => setState(() => _selectedTab = 0),
              ),

              // Center camera button (prominent)
              GestureDetector(
                onTap: () => setState(() => _selectedTab = 1),
                child: Container(
                  width: 56,
                  height: 56,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: _selectedTab == 1
                        ? const Color(0xFFFF4444)
                        : const Color(0xFF2A2A2A),
                    border: Border.all(
                      color: _selectedTab == 1
                          ? const Color(0xFFFF4444)
                          : const Color(0xFF3A3A3A),
                      width: 2,
                    ),
                  ),
                  child: const Icon(Icons.camera_alt,
                      color: Colors.white, size: 26),
                ),
              ),

              _NavItem(
                icon: Icons.event,
                label: 'Events',
                selected: _selectedTab == 2,
                onTap: () => setState(() => _selectedTab = 2),
              ),
              _NavItem(
                icon: Icons.account_circle,
                label: 'Wallet',
                selected: _selectedTab == 3,
                onTap: () => setState(() => _selectedTab = 3),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Nav item ──────────────────────────────────────────────────────────────────

class _NavItem extends StatelessWidget {
  const _NavItem({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = selected ? const Color(0xFFFF4444) : Colors.white38;
    return GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: color, size: 22),
          const SizedBox(height: 2),
          Text(label, style: TextStyle(color: color, fontSize: 10)),
        ],
      ),
    );
  }
}

// ── Events list tab ───────────────────────────────────────────────────────────

class _EventsListTab extends StatefulWidget {
  const _EventsListTab({
    required this.eventRepo,
    required this.nostrService,
  });

  final EventRepository eventRepo;
  final NostrService nostrService;

  @override
  State<_EventsListTab> createState() => _EventsListTabState();
}

class _EventsListTabState extends State<_EventsListTab> {
  @override
  Widget build(BuildContext context) {
    final events = widget.eventRepo.getAllEvents();

    if (events.isEmpty) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.event_busy, color: Colors.white24, size: 56),
            SizedBox(height: 16),
            Text('No events tracked yet.',
                style: TextStyle(color: Colors.white54)),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(12),
      itemCount: events.length,
      itemBuilder: (ctx, i) {
        final event = events[i];
        return ListTile(
          tileColor: const Color(0xFF1A1A1A),
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10)),
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          leading: const Icon(Icons.tag, color: Color(0xFFFF4444)),
          title: Text(
            '#${event.hashtag}',
            style: const TextStyle(
                color: Colors.white, fontWeight: FontWeight.bold),
          ),
          subtitle: Text(
            '${event.posts.length} posts · ${event.participantCount} contributors',
            style: const TextStyle(color: Colors.white54, fontSize: 12),
          ),
          trailing: const Icon(Icons.chevron_right, color: Colors.white30),
          onTap: () => Navigator.of(ctx).push(
            MaterialPageRoute(
              builder: (_) => EventScreen(event: event),
            ),
          ),
        );
      },
    );
  }
}
