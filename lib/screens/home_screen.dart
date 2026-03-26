import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import 'package:mobile/core/tag_normalizer.dart';
import 'package:mobile/features/event/event_repository.dart';
import 'package:mobile/features/event/event_screen.dart';
import 'package:mobile/features/metadata/metadata_service.dart';
import 'package:mobile/features/p2p/p2p_service.dart';
import 'package:mobile/models/event_model.dart';
import 'package:mobile/models/wallet_model.dart';
import 'package:mobile/screens/discover_screen.dart';
import 'package:mobile/screens/feed_screen.dart';
import 'package:mobile/screens/post_composer_screen.dart';
import 'package:mobile/screens/profile_screen.dart';
import 'package:mobile/services/follow_service.dart';
import 'package:mobile/theme/spot_theme.dart';

/// Main app shell with bottom navigation.
List<String> orderedFavoriteEventTags({
  required Iterable<String> followedTags,
  required Iterable<CivicEvent> events,
}) {
  final latestActivityByTag = <String, DateTime>{};
  for (final event in events) {
    final normalizedTag = normalizeTag(event.hashtag);
    if (normalizedTag.isEmpty) continue;
    final latestActivity = event.latestPost?.capturedAt ?? event.firstSeen;
    final existingActivity = latestActivityByTag[normalizedTag];
    if (existingActivity == null || latestActivity.isAfter(existingActivity)) {
      latestActivityByTag[normalizedTag] = latestActivity;
    }
  }

  final tags = followedTags
      .map(normalizeTag)
      .where((tag) => tag.isNotEmpty)
      .toSet()
      .toList(growable: false);
  tags.sort((a, b) {
    final aActivity = latestActivityByTag[a];
    final bActivity = latestActivityByTag[b];
    if (aActivity != null && bActivity != null) {
      return bActivity.compareTo(aActivity);
    }
    if (aActivity != null) return -1;
    if (bActivity != null) return 1;
    return a.compareTo(b);
  });
  return tags;
}

CivicEvent? eventForFavoriteTag(Iterable<CivicEvent> events, String tag) {
  final normalizedTag = normalizeTag(tag);
  if (normalizedTag.isEmpty) return null;
  for (final event in events) {
    if (normalizeTag(event.hashtag) == normalizedTag) return event;
  }
  return null;
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key, required this.wallet});

  final WalletModel wallet;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _selectedTab = 0;
  late final EventRepository _eventRepo;
  final _feedKey = GlobalKey<FeedScreenState>();

  @override
  void initState() {
    super.initState();
    _eventRepo = EventRepository();
    unawaited(MetadataService.instance.syncLegacyProfile(widget.wallet));
    P2PService.instance.configure(wallet: widget.wallet);
    unawaited(P2PService.instance.refreshTransportAvailability());
  }

  @override
  void dispose() {
    _eventRepo.dispose();
    unawaited(P2PService.instance.shutdown());
    super.dispose();
  }

  // Tabs built once and preserved via IndexedStack
  late final List<Widget> _tabs = [
    FeedScreen(key: _feedKey, wallet: widget.wallet, eventRepo: _eventRepo),
    DiscoverScreen(wallet: widget.wallet),
    _EventsListTab(eventRepo: _eventRepo, wallet: widget.wallet),
    ProfileScreen(wallet: widget.wallet, eventRepo: _eventRepo),
  ];

  void _openComposer() {
    showPostComposer(
      context,
      wallet: widget.wallet,
      eventRepo: _eventRepo,
      onPublished: (post) {
        if (!mounted) return;
        setState(() => _selectedTab = 0);
        _feedKey.currentState?.showPublishedPost(post);
      },
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
          ? null
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
      floatingActionButton: _selectedTab != 0
          ? null
          : GestureDetector(
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
      floatingActionButtonLocation: _selectedTab != 0
          ? null
          : FloatingActionButtonLocation.endFloat,
    );
  }

  Widget _buildBottomNav() {
    return Container(
      decoration: const BoxDecoration(color: SpotColors.bg),
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
            child: SizedBox(
              height: 36,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  AnimatedSlide(
                    offset: widget.selected
                        ? const Offset(0, -0.28)
                        : Offset.zero,
                    duration: const Duration(milliseconds: 200),
                    curve: Curves.easeInOut,
                    child: AnimatedSwitcher(
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
                  ),
                  Align(
                    alignment: Alignment.bottomCenter,
                    child: AnimatedOpacity(
                      opacity: widget.selected ? 1.0 : 0.0,
                      duration: const Duration(milliseconds: 200),
                      child: Text(
                        widget.label,
                        style: SpotType.caption.copyWith(
                          color: SpotColors.accent,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ── Events list tab ────────────────────────────────────────────────────────────

class _EventsListTab extends StatefulWidget {
  const _EventsListTab({required this.eventRepo, required this.wallet});

  final EventRepository eventRepo;
  final WalletModel wallet;

  @override
  State<_EventsListTab> createState() => _EventsListTabState();
}

class _EventsListTabState extends State<_EventsListTab> {
  StreamSubscription<CivicEvent>? _eventsSub;
  StreamSubscription<void>? _followSub;
  bool _followReady = false;

  @override
  void initState() {
    super.initState();
    _eventsSub = widget.eventRepo.subscribeToEvents().listen((_) {
      if (mounted) setState(() {});
    });
    unawaited(_initFollowState());
  }

  @override
  void dispose() {
    _eventsSub?.cancel();
    _followSub?.cancel();
    super.dispose();
  }

  Future<void> _initFollowState() async {
    await FollowService.instance.init();
    if (!mounted) return;
    _followSub = FollowService.instance.changes.listen((_) {
      if (mounted) setState(() {});
    });
    setState(() => _followReady = true);
  }

  void _openEvent(BuildContext context, CivicEvent event) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => EventScreen(event: event, wallet: widget.wallet),
      ),
    );
  }

  void _openFavoriteTag(BuildContext context, String tag) {
    final event = eventForFavoriteTag(widget.eventRepo.getAllEvents(), tag);
    if (event != null) {
      _openEvent(context, event);
      return;
    }

    Navigator.of(context).push(
      buildDiscoverScreenRoute(
        wallet: widget.wallet,
        initialSearchQuery: '#$tag',
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final events = widget.eventRepo.getAllEvents();
    final favoriteTags = _followReady
        ? orderedFavoriteEventTags(
            followedTags: FollowService.instance.followedTags,
            events: events,
          )
        : const <String>[];

    if (events.isEmpty && favoriteTags.isEmpty) {
      return const _EventsEmptyState();
    }

    return ListView(
      padding: const EdgeInsets.symmetric(
        horizontal: SpotSpacing.lg,
        vertical: SpotSpacing.lg,
      ),
      children: [
        if (favoriteTags.isNotEmpty) ...[
          _FavoriteTagsSection(
            tags: favoriteTags,
            events: events,
            onTap: (tag) => _openFavoriteTag(context, tag),
          ),
          const SizedBox(height: SpotSpacing.xl),
        ],
        if (events.isEmpty)
          Container(
            padding: const EdgeInsets.all(SpotSpacing.lg),
            decoration: SpotDecoration.card(radius: SpotRadius.sm),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('No live events yet', style: SpotType.body),
                const SizedBox(height: SpotSpacing.xs),
                Text(
                  'Tap a favorite tag above to browse matching threads in Discover.',
                  style: SpotType.caption.copyWith(
                    color: SpotColors.textSecondary,
                  ),
                ),
              ],
            ),
          )
        else ...[
          if (favoriteTags.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: SpotSpacing.sm),
              child: Text(
                'Live Events',
                style: SpotType.label.copyWith(color: SpotColors.textSecondary),
              ),
            ),
          for (int i = 0; i < events.length; i++) ...[
            if (i > 0) const SizedBox(height: SpotSpacing.xs),
            _EventRow(
              event: events[i],
              onTap: () => _openEvent(context, events[i]),
            ),
          ],
        ],
      ],
    );
  }
}

class _FavoriteTagsSection extends StatelessWidget {
  const _FavoriteTagsSection({
    required this.tags,
    required this.events,
    required this.onTap,
  });

  final List<String> tags;
  final List<CivicEvent> events;
  final ValueChanged<String> onTap;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Favorite Tags',
          style: SpotType.label.copyWith(color: SpotColors.textSecondary),
        ),
        const SizedBox(height: SpotSpacing.xs),
        Text(
          'Tap a tag to open its live event or search matching threads.',
          style: SpotType.caption.copyWith(color: SpotColors.textTertiary),
        ),
        const SizedBox(height: SpotSpacing.md),
        Wrap(
          spacing: SpotSpacing.sm,
          runSpacing: SpotSpacing.sm,
          children: [
            for (final tag in tags)
              _FavoriteTagChip(
                tag: tag,
                event: eventForFavoriteTag(events, tag),
                onTap: () => onTap(tag),
              ),
          ],
        ),
      ],
    );
  }
}

class _FavoriteTagChip extends StatelessWidget {
  const _FavoriteTagChip({
    required this.tag,
    required this.event,
    required this.onTap,
  });

  final String tag;
  final CivicEvent? event;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final hasLiveEvent = event != null;
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: SpotSpacing.md,
          vertical: SpotSpacing.sm,
        ),
        decoration: BoxDecoration(
          color: hasLiveEvent
              ? SpotColors.accent.withValues(alpha: 0.12)
              : SpotColors.surface,
          borderRadius: BorderRadius.circular(SpotRadius.full),
          border: Border.all(
            color: hasLiveEvent ? SpotColors.accent : SpotColors.border,
            width: 0.5,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '#$tag',
              style: SpotType.label.copyWith(
                color: hasLiveEvent
                    ? SpotColors.accent
                    : SpotColors.textPrimary,
              ),
            ),
            if (hasLiveEvent) ...[
              const SizedBox(width: SpotSpacing.xs),
              Text(
                'Live',
                style: SpotType.caption.copyWith(color: SpotColors.accent),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _EventRow extends StatelessWidget {
  const _EventRow({required this.event, required this.onTap});

  final CivicEvent event;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
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
            const Icon(
              CupertinoIcons.chevron_right,
              color: SpotColors.overlay,
              size: 16,
            ),
          ],
        ),
      ),
    );
  }
}

class _EventsEmptyState extends StatelessWidget {
  const _EventsEmptyState();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            CupertinoIcons.folder,
            color: SpotColors.overlay,
            size: 40,
          ),
          const SizedBox(height: SpotSpacing.lg),
          Text(
            'No events yet',
            style: SpotType.bodySecondary.copyWith(fontWeight: FontWeight.w300),
          ),
        ],
      ),
    );
  }
}
