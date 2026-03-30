import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import 'package:mobile/features/metadata/metadata_service.dart';
import 'package:mobile/models/asset_transport_policy.dart';
import 'package:mobile/models/profile_model.dart';
import 'package:mobile/models/wallet_model.dart';
import 'package:mobile/screens/altcha_gate_screen.dart';
import 'package:mobile/screens/asset_transport_settings_screen.dart';
import 'package:mobile/screens/interests_screen.dart';
import 'package:mobile/screens/my_posts_screen.dart';
import 'package:mobile/screens/onboarding_screen.dart';
import 'package:mobile/screens/wallet_screen.dart';
import 'package:mobile/services/app_data_reset_service.dart';
import 'package:mobile/services/cache_manager.dart';
import 'package:mobile/services/follow_service.dart';
import 'package:mobile/services/local_post_store.dart';
import 'package:mobile/services/session_logout_service.dart';
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

typedef LoadSettingsProfile = Future<ProfileModel> Function(WalletModel wallet);
typedef SaveProfileVisibility =
    Future<ProfileModel> Function(
      WalletModel wallet, {
      bool? threadsPublic,
      bool? repliesPublic,
      bool? footprintMapPublic,
    });

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({
    super.key,
    required this.wallet,
    this.loadProfileSettings,
    this.saveProfileVisibility,
  });

  final WalletModel wallet;
  final LoadSettingsProfile? loadProfileSettings;
  final SaveProfileVisibility? saveProfileVisibility;

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool _isLoggingOut = false;
  bool _isLoadingVisibility = true;
  bool _isSavingVisibility = false;
  bool _threadsPublic = true;
  bool _repliesPublic = true;
  bool _footprintMapPublic = false;

  AssetTransportPolicy get _assetTransportPolicy =>
      UserPrefsService.instance.assetTransportPolicy;
  String get _favoriteTopicsValue =>
      favoriteTopicsSummary(UserPrefsService.instance.interests);

  LoadSettingsProfile get _profileLoader =>
      widget.loadProfileSettings ??
      MetadataService.instance.fetchCurrentProfile;
  SaveProfileVisibility get _visibilitySaver =>
      widget.saveProfileVisibility ??
      (wallet, {threadsPublic, repliesPublic, footprintMapPublic}) =>
          MetadataService.instance.updateCurrentProfileVisibility(
            wallet: wallet,
            threadsPublic: threadsPublic,
            repliesPublic: repliesPublic,
            footprintMapPublic: footprintMapPublic,
          );

  @override
  void initState() {
    super.initState();
    unawaited(_loadProfileVisibility());
  }

  void _applyProfileVisibility(ProfileModel profile) {
    _threadsPublic = profile.areThreadsPublic;
    _repliesPublic = profile.areRepliesPublic;
    _footprintMapPublic = profile.isFootprintMapPublic;
  }

  Future<void> _loadProfileVisibility() async {
    try {
      final profile = await _profileLoader(widget.wallet);
      if (!mounted) return;
      setState(() {
        _applyProfileVisibility(profile);
        _isLoadingVisibility = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _isLoadingVisibility = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to load privacy settings: $error')),
      );
    }
  }

  Future<void> _saveVisibility({
    bool? threadsPublic,
    bool? repliesPublic,
    bool? footprintMapPublic,
  }) async {
    if (_isSavingVisibility) return;

    final previousThreadsPublic = _threadsPublic;
    final previousRepliesPublic = _repliesPublic;
    final previousFootprintMapPublic = _footprintMapPublic;

    setState(() {
      if (threadsPublic != null) {
        _threadsPublic = threadsPublic;
      }
      if (repliesPublic != null) {
        _repliesPublic = repliesPublic;
      }
      if (footprintMapPublic != null) {
        _footprintMapPublic = footprintMapPublic;
      }
      _isSavingVisibility = true;
    });

    try {
      final profile = await _visibilitySaver(
        widget.wallet,
        threadsPublic: threadsPublic,
        repliesPublic: repliesPublic,
        footprintMapPublic: footprintMapPublic,
      );
      if (!mounted) return;
      setState(() {
        _applyProfileVisibility(profile);
        _isSavingVisibility = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _threadsPublic = previousThreadsPublic;
        _repliesPublic = previousRepliesPublic;
        _footprintMapPublic = previousFootprintMapPublic;
        _isSavingVisibility = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to update privacy settings: $error')),
      );
    }
  }

  Future<void> _setThreadsPublic(bool isPublic) async {
    await _saveVisibility(threadsPublic: isPublic);
  }

  Future<void> _setRepliesPublic(bool isPublic) async {
    await _saveVisibility(repliesPublic: isPublic);
  }

  Future<void> _setFootprintMapPublic(bool isPublic) async {
    await _saveVisibility(footprintMapPublic: isPublic);
  }

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
      await LocalPostStore.instance.runWithWritesPaused(() async {
        await Future.wait([
          CacheManager.instance.purgeAll(),
          CacheManager.instance.clearBlocklist(),
          LocalPostStore.instance.clearAll(force: true),
          FollowService.instance.clearAll(),
          UserPrefsService.instance.clearAll(),
        ]);
        AppDataResetService.instance.notifyLocalDataCleared();
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Local data cleared. Restart app to re-sync.'),
          ),
        );
      }
    }
  }

  Future<void> _confirmLogout() async {
    if (_isLoggingOut) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: SpotColors.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(SpotRadius.md),
        ),
        title: const Text('Log out?', style: SpotType.subheading),
        content: const Text(
          'Before logging out, make sure you have saved your 12-word recovery '
          'phrase. You will need it to restore this same identity later. '
          'Logging out will sign you out on this device and erase local app '
          'data. Your Supabase account and remote posts will remain intact.',
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
              'Log Out',
              style: SpotType.body.copyWith(color: SpotColors.danger),
            ),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await _logout();
    }
  }

  Future<void> _logout() async {
    if (_isLoggingOut) return;
    setState(() => _isLoggingOut = true);
    try {
      await SessionLogoutService.instance.logout();
      if (!mounted) return;
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute<void>(
          builder: (_) => const AltchaGateScreen(next: OnboardingScreen()),
        ),
        (route) => false,
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Failed to log out: $error')));
      setState(() => _isLoggingOut = false);
    }
  }

  Future<void> _openPublicActivityMenu() async {
    final selection = await showCupertinoModalPopup<MyPostsScreenMode>(
      context: context,
      builder: (ctx) => CupertinoActionSheet(
        title: const Text('Public Activity'),
        message: const Text('Choose which of your public posts to open.'),
        actions: [
          CupertinoActionSheetAction(
            onPressed: () => Navigator.of(ctx).pop(MyPostsScreenMode.threads),
            child: const Text('Posted Threads'),
          ),
          CupertinoActionSheetAction(
            onPressed: () => Navigator.of(ctx).pop(MyPostsScreenMode.replies),
            child: const Text('Replied Threads'),
          ),
        ],
        cancelButton: CupertinoActionSheetAction(
          onPressed: () => Navigator.of(ctx).pop(),
          child: const Text('Cancel'),
        ),
      ),
    );

    if (!mounted || selection == null) return;
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => MyPostsScreen(wallet: widget.wallet, mode: selection),
      ),
    );
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
          const SizedBox(height: SpotSpacing.sm),
          _SettingsRow(
            icon: CupertinoIcons.list_bullet,
            label: 'View My Activity',
            onTap: _openPublicActivityMenu,
          ),
          const SizedBox(height: SpotSpacing.xl),
          const Padding(
            padding: EdgeInsets.symmetric(vertical: SpotSpacing.sm),
            child: Text('PRIVACY', style: SpotType.label),
          ),
          _SettingsSwitchRow(
            icon: CupertinoIcons.map,
            label: 'Footprint Map',
            value: _footprintMapPublic,
            onChanged: _isLoadingVisibility || _isSavingVisibility
                ? null
                : _setFootprintMapPublic,
          ),
          const SizedBox(height: SpotSpacing.sm),
          _SettingsSwitchRow(
            icon: CupertinoIcons.text_bubble,
            label: 'Public Threads',
            value: _threadsPublic,
            onChanged: _isLoadingVisibility || _isSavingVisibility
                ? null
                : _setThreadsPublic,
          ),
          const SizedBox(height: SpotSpacing.sm),
          _SettingsSwitchRow(
            icon: CupertinoIcons.reply,
            label: 'Public Replies',
            value: _repliesPublic,
            onChanged: _isLoadingVisibility || _isSavingVisibility
                ? null
                : _setRepliesPublic,
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
          const SizedBox(height: SpotSpacing.xl),
          const Padding(
            padding: EdgeInsets.symmetric(vertical: SpotSpacing.sm),
            child: Text('SESSION', style: SpotType.label),
          ),
          _SettingsRow(
            icon: CupertinoIcons.square_arrow_right,
            label: 'Log Out',
            value: _isLoggingOut ? 'Signing out…' : null,
            onTap: _confirmLogout,
          ),
          const SizedBox(height: SpotSpacing.xxl),
        ],
      ),
    );
  }
}

class _SettingsSwitchRow extends StatelessWidget {
  const _SettingsSwitchRow({
    required this.icon,
    required this.label,
    required this.value,
    required this.onChanged,
  });

  final IconData icon;
  final String label;
  final bool value;
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onChanged == null ? null : () => onChanged!(!value),
      borderRadius: BorderRadius.circular(SpotRadius.md),
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: SpotSpacing.lg,
          vertical: SpotSpacing.sm,
        ),
        decoration: SpotDecoration.cardBordered(),
        child: Row(
          children: [
            Icon(icon, size: 20, color: SpotColors.textSecondary),
            const SizedBox(width: SpotSpacing.md),
            Expanded(child: Text(label, style: SpotType.body)),
            Switch.adaptive(value: value, onChanged: onChanged),
          ],
        ),
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
