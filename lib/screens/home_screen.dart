import 'package:flutter/material.dart';

import 'package:mobile/features/camera/camera_screen.dart';
import 'package:mobile/features/event/event_repository.dart';
import 'package:mobile/features/event/event_screen.dart';
import 'package:mobile/features/nostr/nostr_service.dart';
import 'package:mobile/models/wallet_model.dart';
import 'package:mobile/screens/feed_screen.dart';
import 'package:mobile/screens/my_posts_screen.dart';
import 'package:mobile/screens/wallet_screen.dart';
import 'package:mobile/theme/spot_theme.dart';

/// Main app shell with bottom navigation.
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key, required this.wallet});

  final WalletModel wallet;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _selectedTab = 0;
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

  Widget _buildCurrentTab() {
    switch (_selectedTab) {
      case 0:
        return FeedScreen(nostrService: _nostrService);
      case 1:
        return CameraScreen(wallet: widget.wallet, nostrService: _nostrService);
      case 2:
        return _EventsListTab(eventRepo: _eventRepo);
      case 3:
        return WalletScreen(wallet: widget.wallet);
      default:
        return FeedScreen(nostrService: _nostrService);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: SpotColors.bg,
      appBar: _selectedTab == 1
          ? null
          : AppBar(
              backgroundColor: SpotColors.bg,
              title: const Text('Spot', style: SpotType.wordmark),
              actions: _selectedTab == 3
                  ? [
                      IconButton(
                        icon: const Icon(Icons.grid_on_outlined, size: 18),
                        color: SpotColors.textSecondary,
                        tooltip: 'My Posts',
                        onPressed: () => Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => MyPostsScreen(
                              wallet: widget.wallet,
                              nostrService: _nostrService,
                            ),
                          ),
                        ),
                      ),
                    ]
                  : const [],
            ),
      body: _buildCurrentTab(),
      bottomNavigationBar: _buildBottomNav(),
    );
  }

  Widget _buildBottomNav() {
    return Container(
      decoration: const BoxDecoration(
        color: SpotColors.bg,
        border: Border(top: BorderSide(color: SpotColors.border, width: 0.5)),
      ),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: SpotSpacing.sm),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _NavItem(
                icon: Icons.view_stream_outlined,
                label: 'Feed',
                selected: _selectedTab == 0,
                onTap: () => setState(() => _selectedTab = 0),
              ),
              // Capture button — center focal point
              GestureDetector(
                onTap: () => setState(() => _selectedTab = 1),
                child: Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: _selectedTab == 1 ? SpotColors.accent : Colors.transparent,
                    border: Border.all(
                      color: _selectedTab == 1
                          ? SpotColors.accent
                          : SpotColors.border,
                      width: 0.5,
                    ),
                  ),
                  child: Icon(
                    Icons.radio_button_unchecked,
                    color: _selectedTab == 1
                        ? SpotColors.onAccent
                        : SpotColors.textSecondary,
                    size: 22,
                  ),
                ),
              ),
              _NavItem(
                icon: Icons.folder_open_outlined,
                label: 'Events',
                selected: _selectedTab == 2,
                onTap: () => setState(() => _selectedTab = 2),
              ),
              _NavItem(
                icon: Icons.person_outline,
                label: 'Identity',
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
    final color = selected ? SpotColors.accent : SpotColors.textSecondary;
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: SpotSpacing.lg, vertical: SpotSpacing.xs),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: color, size: 20),
            const SizedBox(height: 3),
            Text(label, style: SpotType.caption.copyWith(color: color)),
          ],
        ),
      ),
    );
  }
}

// ── Events list tab ────────────────────────────────────────────────────────────

class _EventsListTab extends StatelessWidget {
  const _EventsListTab({required this.eventRepo});

  final EventRepository eventRepo;

  @override
  Widget build(BuildContext context) {
    final events = eventRepo.getAllEvents();

    if (events.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.folder_open_outlined, color: SpotColors.overlay, size: 40),
            const SizedBox(height: SpotSpacing.lg),
            Text(
              'No events yet',
              style: SpotType.bodySecondary.copyWith(fontWeight: FontWeight.w300),
            ),
          ],
        ),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.symmetric(
        horizontal: SpotSpacing.lg,
        vertical: SpotSpacing.lg,
      ),
      itemCount: events.length,
      separatorBuilder: (context, i) => const SizedBox(height: SpotSpacing.xs),
      itemBuilder: (ctx, i) {
        final event = events[i];
        return InkWell(
          onTap: () => Navigator.of(ctx).push(
            MaterialPageRoute(builder: (_) => EventScreen(event: event)),
          ),
          borderRadius: BorderRadius.circular(SpotRadius.sm),
          child: Container(
            padding: const EdgeInsets.symmetric(
              horizontal: SpotSpacing.lg,
              vertical: SpotSpacing.md,
            ),
            decoration: SpotDecoration.card(radius: SpotRadius.sm),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('#${event.hashtag}', style: SpotType.body),
                      const SizedBox(height: 3),
                      Text(
                        '${event.posts.length} posts · ${event.participantCount} contributors',
                        style: SpotType.caption,
                      ),
                    ],
                  ),
                ),
                const Icon(Icons.chevron_right, color: SpotColors.overlay, size: 16),
              ],
            ),
          ),
        );
      },
    );
  }
}
