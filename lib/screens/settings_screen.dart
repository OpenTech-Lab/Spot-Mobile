import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import 'package:mobile/models/asset_transport_policy.dart';
import 'package:mobile/models/wallet_model.dart';
import 'package:mobile/screens/asset_transport_settings_screen.dart';
import 'package:mobile/screens/interests_screen.dart';
import 'package:mobile/screens/wallet_screen.dart';
import 'package:mobile/services/cache_manager.dart';
import 'package:mobile/services/follow_service.dart';
import 'package:mobile/services/local_post_store.dart';
import 'package:mobile/services/user_prefs_service.dart';
import 'package:mobile/theme/spot_theme.dart';

String favoriteTopicsSummary(Iterable<String> topics) {
  final unique = topics
      .map((topic) => topic.trim())
      .where((topic) => topic.isNotEmpty)
      .toList(growable: false);
  if (unique.isEmpty) return 'Not set';
  if (unique.length <= 2) return unique.map((topic) => '#$topic').join(', ');
  return '#${unique[0]}, #${unique[1]} +${unique.length - 2}';
}

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key, required this.wallet});

  final WalletModel wallet;

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  AssetTransportPolicy get _assetTransportPolicy =>
      UserPrefsService.instance.assetTransportPolicy;
  String get _favoriteTopicsValue =>
      favoriteTopicsSummary(UserPrefsService.instance.interests);

  Future<void> _openAssetTransportSettings() async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const AssetTransportSettingsScreen()),
    );
    if (mounted) {
      setState(() {});
    }
  }

  Future<void> _openFavoriteTopics() async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => InterestsScreen(
        onDone: () {
          if (mounted) {
            setState(() {});
          }
        },
      ),
    );
    if (mounted) {
      setState(() {});
    }
  }

  Future<void> _clearCache() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: SpotColors.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(SpotRadius.md),
        ),
        title: const Text('Clear Cache', style: SpotType.subheading),
        content: const Text(
          'This will delete all cached media files. '
          'Your posts and settings will not be affected.',
          style: SpotType.bodySecondary,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel', style: SpotType.bodySecondary),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(
              'Clear',
              style: SpotType.body.copyWith(color: SpotColors.danger),
            ),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      await CacheManager.instance.purgeAll();
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Cache cleared')));
      }
    }
  }

  Future<void> _clearAllData() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: SpotColors.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(SpotRadius.md),
        ),
        title: const Text('Clear Local Data', style: SpotType.subheading),
        content: const Text(
          'This will delete ALL local data including:\n'
          '• Cached media\n'
          '• Saved posts\n'
          '• Favorite tags and preferences\n'
          '• Blocklist\n\n'
          'Your account will NOT be deleted. '
          'Remote data will re-sync from Supabase.',
          style: SpotType.bodySecondary,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel', style: SpotType.bodySecondary),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(
              'Clear All',
              style: SpotType.body.copyWith(color: SpotColors.danger),
            ),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      await Future.wait([
        CacheManager.instance.purgeAll(),
        CacheManager.instance.clearBlocklist(),
        LocalPostStore.instance.clearAll(),
        FollowService.instance.clearAll(),
        UserPrefsService.instance.clearAll(),
      ]);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Local data cleared. Restart app to re-sync.'),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: SpotColors.bg,
      appBar: AppBar(
        backgroundColor: SpotColors.bg,
        title: const Text('Settings', style: SpotType.subheading),
      ),
      body: ListView(
        padding: const EdgeInsets.symmetric(
          horizontal: SpotSpacing.lg,
          vertical: SpotSpacing.lg,
        ),
        children: [
          _SettingsRow(
            icon: CupertinoIcons.star,
            label: 'Favorite Topics',
            value: _favoriteTopicsValue,
            onTap: _openFavoriteTopics,
          ),
          const SizedBox(height: SpotSpacing.sm),
          _SettingsRow(
            icon: CupertinoIcons.wifi,
            label: 'Asset Transport',
            value: _assetTransportPolicy.label,
            onTap: _openAssetTransportSettings,
          ),
          const SizedBox(height: SpotSpacing.sm),
          _SettingsRow(
            icon: CupertinoIcons.person_crop_circle,
            label: 'Account',
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => WalletScreen(wallet: widget.wallet),
              ),
            ),
          ),
          const SizedBox(height: SpotSpacing.xl),
          const Padding(
            padding: EdgeInsets.symmetric(vertical: SpotSpacing.sm),
            child: Text('Storage', style: SpotType.label),
          ),
          _SettingsRow(
            icon: CupertinoIcons.trash,
            label: 'Clear Cache',
            onTap: _clearCache,
          ),
          const SizedBox(height: SpotSpacing.sm),
          _SettingsRow(
            icon: CupertinoIcons.delete,
            label: 'Clear Local Data',
            onTap: _clearAllData,
          ),
        ],
      ),
    );
  }
}

class _SettingsRow extends StatelessWidget {
  const _SettingsRow({
    required this.icon,
    required this.label,
    required this.onTap,
    this.value,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final String? value;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(SpotRadius.md),
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: SpotSpacing.lg,
          vertical: SpotSpacing.md,
        ),
        decoration: SpotDecoration.cardBordered(),
        child: Row(
          children: [
            Icon(icon, size: 20, color: SpotColors.textSecondary),
            const SizedBox(width: SpotSpacing.md),
            Expanded(child: Text(label, style: SpotType.body)),
            if (value != null) ...[
              const SizedBox(width: SpotSpacing.sm),
              Text(
                value!,
                style: SpotType.caption.copyWith(
                  color: SpotColors.textTertiary,
                ),
              ),
              const SizedBox(width: SpotSpacing.xs),
            ],
            const Icon(
              CupertinoIcons.chevron_right,
              size: 14,
              color: SpotColors.textTertiary,
            ),
          ],
        ),
      ),
    );
  }
}
