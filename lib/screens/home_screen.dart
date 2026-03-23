import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import 'package:mobile/features/event/event_repository.dart';
import 'package:mobile/features/event/event_screen.dart';
import 'package:mobile/features/nostr/nostr_service.dart';
import 'package:mobile/models/wallet_model.dart';
import 'package:mobile/screens/discover_screen.dart';
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
  final _feedKey = GlobalKey<FeedScreenState>();

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
    FeedScreen(key: _feedKey, nostrService: _nostrService, wallet: widget.wallet),
    DiscoverScreen(nostrService: _nostrService, wallet: widget.wallet),
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
      appBar: _selectedTab == 3
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
              : _selectedTab == 1
                  ? AppBar(
                      backgroundColor: SpotColors.bg,
                      title: const Text('Discover', style: SpotType.subheading),
                    )
                  : AppBar(
                      backgroundColor: SpotColors.bg,
                      title: const Text('Events', style: SpotType.subheading),
                    ),
      body: Stack(
        children: [
          for (int i = 0; i < _tabs.length; i++)
            IgnorePointer(
              ignoring: _selectedTab != i,
              child: AnimatedOpacity(
                opacity: _selectedTab == i ? 1.0 : 0.0,
                duration: const Duration(milliseconds: 220),
                curve: Curves.easeInOut,
                child: _tabs[i],
              ),
            ),
        ],
      ),
      bottomNavigationBar: _buildBottomNav(),
      floatingActionButton: _selectedTab != 0 && _selectedTab != 1 ? null : GestureDetector(
        onTap: _openComposer,
        child: Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: SpotColors.bg,
          ),
          child: const Icon(
            CupertinoIcons.plus,
            color: SpotColors.textSecondary,
            size: 22,
          ),
        ),
      ),
      floatingActionButtonLocation: _selectedTab != 0 && _selectedTab != 1 ? null : FloatingActionButtonLocation.endFloat,
    );
  }

  Widget _buildBottomNav() {
    return Container(
      decoration: const BoxDecoration(
        color: SpotColors.bg,
      ),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: SpotSpacing.sm),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _NavItem(
                icon: CupertinoIcons.house,
                selectedIcon: CupertinoIcons.house_fill,
                label: 'Home',
                selected: _selectedTab == 0,
                onTap: () => setState(() => _selectedTab = 0),
                onDoubleTap: () {
                  setState(() => _selectedTab = 0);
                  _feedKey.currentState?.triggerRefresh();
                },
              ),
              _NavItem(
                icon: CupertinoIcons.compass,
                label: 'Discover',
                selected: _selectedTab == 1,
                onTap: () => setState(() => _selectedTab = 1),
              ),
              _NavItem(
                icon: CupertinoIcons.folder,
                selectedIcon: CupertinoIcons.folder_fill,
                label: 'Events',
                selected: _selectedTab == 2,
                onTap: () => setState(() => _selectedTab = 2),
              ),
              _NavItem(
                icon: CupertinoIcons.person,
                selectedIcon: CupertinoIcons.person_fill,
                label: 'Profile',
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

class _NavItem extends StatefulWidget {
  const _NavItem({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
    this.selectedIcon,
    this.onDoubleTap,
  });

  final IconData icon;
  final IconData? selectedIcon;
  final String label;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback? onDoubleTap;

  @override
  State<_NavItem> createState() => _NavItemState();
}

class _NavItemState extends State<_NavItem>
    with SingleTickerProviderStateMixin {
  late final AnimationController _scaleCtrl;

  @override
  void initState() {
    super.initState();
    _scaleCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 70),
      reverseDuration: const Duration(milliseconds: 300),
      lowerBound: 0.82,
      upperBound: 1.0,
      value: 1.0,
    );
  }

  @override
  void dispose() {
    _scaleCtrl.dispose();
    super.dispose();
  }

  void _onTapDown(TapDownDetails _) => _scaleCtrl.reverse();
  void _onTapUp(TapUpDetails _) => _scaleCtrl.fling(velocity: 1.5);
  void _onTapCancel() => _scaleCtrl.fling(velocity: 1.5);

  @override
  Widget build(BuildContext context) {
    final activeIcon = widget.selectedIcon ?? widget.icon;
    final currentIcon = widget.selected ? activeIcon : widget.icon;

    return GestureDetector(
      onTap: widget.onTap,
      onDoubleTap: widget.onDoubleTap,
      onTapDown: _onTapDown,
      onTapUp: _onTapUp,
      onTapCancel: _onTapCancel,
      behavior: HitTestBehavior.opaque,
      child: ScaleTransition(
        scale: CurvedAnimation(
          parent: _scaleCtrl,
          curve: Curves.easeOut,
          reverseCurve: Curves.easeIn,
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: SpotSpacing.sm,
            vertical: SpotSpacing.xs,
          ),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeInOut,
            padding: const EdgeInsets.symmetric(
              horizontal: SpotSpacing.lg,
              vertical: SpotSpacing.xs,
            ),
            decoration: BoxDecoration(
              color: widget.selected
                  ? SpotColors.accent.withValues(alpha: 0.12)
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 200),
                  transitionBuilder: (child, anim) => ScaleTransition(
                    scale: CurvedAnimation(
                      parent: anim,
                      curve: Curves.easeOutBack,
                    ),
                    child: child,
                  ),
                  child: Icon(
                    currentIcon,
                    key: ValueKey(currentIcon),
                    color: widget.selected
                        ? SpotColors.accent
                        : SpotColors.textSecondary,
                    size: 20,
                  ),
                ),
                const SizedBox(height: 3),
                AnimatedDefaultTextStyle(
                  duration: const Duration(milliseconds: 200),
                  style: SpotType.caption.copyWith(
                    color: widget.selected
                        ? SpotColors.accent
                        : SpotColors.textSecondary,
                    fontWeight: widget.selected
                        ? FontWeight.w600
                        : FontWeight.w400,
                  ),
                  child: Text(widget.label),
                ),
              ],
            ),
          ),
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
