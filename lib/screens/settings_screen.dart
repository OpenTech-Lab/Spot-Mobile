import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import 'package:mobile/features/nostr/nostr_service.dart';
import 'package:mobile/models/asset_transport_policy.dart';
import 'package:mobile/models/wallet_model.dart';
import 'package:mobile/screens/asset_transport_settings_screen.dart';
import 'package:mobile/screens/relay_list_screen.dart';
import 'package:mobile/screens/wallet_screen.dart';
import 'package:mobile/services/cache_manager.dart';
import 'package:mobile/services/local_post_store.dart';
import 'package:mobile/services/user_prefs_service.dart';
import 'package:mobile/theme/spot_theme.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({
    super.key,
    required this.wallet,
    required this.nostrService,
  });

  final WalletModel wallet;
  final NostrService nostrService;

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  AssetTransportPolicy get _assetTransportPolicy =>
      UserPrefsService.instance.assetTransportPolicy;

  Future<void> _openAssetTransportSettings() async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const AssetTransportSettingsScreen()),
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
            child: Text('Clear', style: SpotType.body.copyWith(color: SpotColors.danger)),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      await CacheManager.instance.purgeAll();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Cache cleared')),
        );
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
        title: const Text('Clear All Data', style: SpotType.subheading),
        content: const Text(
          'This will delete ALL local data including:\n'
          '• Cached media\n'
          '• Saved posts\n'
          '• Blocklist\n\n'
          'Your identity will NOT be deleted. '
          'Posts will re-sync from relays.',
          style: SpotType.bodySecondary,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel', style: SpotType.bodySecondary),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text('Clear All', style: SpotType.body.copyWith(color: SpotColors.danger)),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      await Future.wait([
        CacheManager.instance.purgeAll(),
        CacheManager.instance.clearBlocklist(),
        LocalPostStore.instance.clearAll(),
      ]);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('All data cleared. Restart app to re-sync.')),
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
            icon: CupertinoIcons.antenna_radiowaves_left_right,
            label: 'Relay List',
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) =>
                    RelayListScreen(nostrService: widget.nostrService),
              ),
            ),
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
            label: 'Identity',
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
            label: 'Clear All Data',
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
