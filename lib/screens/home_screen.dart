import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import 'package:mobile/features/event/event_repository.dart';
import 'package:mobile/features/event/event_screen.dart';
import 'package:mobile/features/nostr/nostr_service.dart';
import 'package:mobile/models/wallet_model.dart';
import 'package:mobile/screens/feed_screen.dart';
import 'package:mobile/screens/post_composer_screen.dart';
import 'package:mobile/screens/profile_screen.dart';
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

  // Tabs built once and preserved via IndexedStack
  late final List<Widget> _tabs = [
    FeedScreen(nostrService: _nostrService, wallet: widget.wallet),
    _EventsListTab(
      eventRepo: _eventRepo,
      nostrService: _nostrService,
      wallet: widget.wallet,
    ),
    ProfileScreen(wallet: widget.wallet, nostrService: _nostrService),
  ];

  void _openComposer() {
    showPostComposer(
      context,
      wallet: widget.wallet,
      nostrService: _nostrService,
      eventRepo: _eventRepo,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: SpotColors.bg,
      appBar: _selectedTab == 2
          ? null // ProfileScreen provides its own AppBar with settings button
          : _selectedTab == 0
              ? AppBar(
                  backgroundColor: SpotColors.bg,
                  centerTitle: true,
                  title: Image.asset(
                    'assets/logo_transparent.png',
                    height: 28,
                    fit: BoxFit.contain,
                  ),
                )
              : AppBar(
                  backgroundColor: SpotColors.bg,
                  title: const Text('Events', style: SpotType.subheading),
                ),
      body: IndexedStack(index: _selectedTab, children: _tabs),
      bottomNavigationBar: _buildBottomNav(),
      floatingActionButton: _selectedTab != 0 ? null : GestureDetector(
        onTap: _openComposer,
        child: Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: SpotColors.bg,
            border: Border.all(color: SpotColors.border, width: 0.5),
          ),
          child: const Icon(
            CupertinoIcons.plus,
            color: SpotColors.textSecondary,
            size: 22,
          ),
        ),
      ),
      floatingActionButtonLocation: _selectedTab != 0 ? null : FloatingActionButtonLocation.endFloat,
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
                icon: CupertinoIcons.list_bullet,
                label: 'Home',
                selected: _selectedTab == 0,
                onTap: () => setState(() => _selectedTab = 0),
              ),
              _NavItem(
                icon: CupertinoIcons.folder,
                label: 'Events',
                selected: _selectedTab == 1,
                onTap: () => setState(() => _selectedTab = 1),
              ),
              _NavItem(
                icon: CupertinoIcons.person,
                label: 'Profile',
                selected: _selectedTab == 2,
                onTap: () => setState(() => _selectedTab = 2),
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
  const _EventsListTab({
    required this.eventRepo,
    required this.nostrService,
    required this.wallet,
  });

  final EventRepository eventRepo;
  final NostrService nostrService;
  final WalletModel wallet;

  @override
  Widget build(BuildContext context) {
    final events = eventRepo.getAllEvents();

    if (events.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(CupertinoIcons.folder, color: SpotColors.overlay, size: 40),
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
            MaterialPageRoute(
              builder: (_) => EventScreen(
                event: event,
                nostrService: nostrService,
                wallet: wallet,
              ),
            ),
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
                const Icon(CupertinoIcons.chevron_right, color: SpotColors.overlay, size: 16),
              ],
            ),
          ),
        );
      },
    );
  }
}
