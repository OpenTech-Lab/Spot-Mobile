import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import 'package:mobile/features/p2p/p2p_service.dart';
import 'package:mobile/l10n/app_localizations.dart';
import 'package:mobile/models/asset_transport_policy.dart';
import 'package:mobile/services/user_prefs_service.dart';
import 'package:mobile/theme/spot_theme.dart';

class AssetTransportSettingsScreen extends StatefulWidget {
  const AssetTransportSettingsScreen({super.key});

  @override
  State<AssetTransportSettingsScreen> createState() =>
      _AssetTransportSettingsScreenState();
}

class _AssetTransportSettingsScreenState
    extends State<AssetTransportSettingsScreen> {
  late AssetTransportPolicy _selectedPolicy;
  late bool _cdnEnabled;
  late bool _cdnUploadEnabled;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _selectedPolicy = UserPrefsService.instance.assetTransportPolicy;
    _cdnEnabled = UserPrefsService.instance.cdnEnabled;
    _cdnUploadEnabled = UserPrefsService.instance.cdnUploadEnabled;
  }

  Future<void> _selectPolicy(AssetTransportPolicy policy) async {
    if (_isSaving || policy == _selectedPolicy) return;
    setState(() {
      _selectedPolicy = policy;
      _isSaving = true;
    });

    await UserPrefsService.instance.saveAssetTransportPolicy(policy);
    await P2PService.instance.refreshTransportAvailability();

    if (!mounted) return;
    setState(() => _isSaving = false);
  }

  Future<void> _onCdnEnabledChanged(bool value) async {
    if (_isSaving) return;
    setState(() {
      _cdnEnabled = value;
      if (!value) _cdnUploadEnabled = false;
      _isSaving = true;
    });

    await UserPrefsService.instance.saveCdnEnabled(value);
    if (!value) {
      await UserPrefsService.instance.saveCdnUploadEnabled(false);
    }

    if (!mounted) return;
    setState(() => _isSaving = false);
  }

  Future<void> _onCdnUploadChanged(bool value) async {
    if (_isSaving) return;
    setState(() {
      _cdnUploadEnabled = value;
      _isSaving = true;
    });

    await UserPrefsService.instance.saveCdnUploadEnabled(value);

    if (!mounted) return;
    setState(() => _isSaving = false);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Scaffold(
      backgroundColor: SpotColors.bg,
      appBar: AppBar(
        backgroundColor: SpotColors.bg,
        title: Text(l10n.assetTransportScreenTitle, style: SpotType.subheading),
      ),
      body: ListView(
        padding: const EdgeInsets.symmetric(
          horizontal: SpotSpacing.lg,
          vertical: SpotSpacing.lg,
        ),
        children: [
          // ── P2P transport policy ──────────────────────────────────────
          Text(
            l10n.peerTransportSection,
            style: SpotType.subheading.copyWith(fontSize: 14),
          ),
          const SizedBox(height: SpotSpacing.sm),
          Text(
            l10n.peerTransportDescription,
            style: SpotType.bodySecondary.copyWith(
              color: SpotColors.textSecondary,
            ),
          ),
          const SizedBox(height: SpotSpacing.lg),
          for (final policy in AssetTransportPolicy.values) ...[
            _PolicyOptionCard(
              policy: policy,
              selected: _selectedPolicy == policy,
              enabled: !_isSaving,
              onTap: () => _selectPolicy(policy),
              l10n: l10n,
            ),
            if (policy != AssetTransportPolicy.values.last)
              const SizedBox(height: SpotSpacing.sm),
          ],

          // ── CDN acceleration ──────────────────────────────────────────
          const SizedBox(height: SpotSpacing.xl),
          Text(
            l10n.cdnAccelerationSection,
            style: SpotType.subheading.copyWith(fontSize: 14),
          ),
          const SizedBox(height: SpotSpacing.sm),
          Text(
            l10n.cdnAccelerationDescription,
            style: SpotType.bodySecondary.copyWith(
              color: SpotColors.textSecondary,
            ),
          ),
          const SizedBox(height: SpotSpacing.md),
          _ToggleRow(
            label: l10n.cdnFetchLabel,
            description: l10n.cdnFetchDescription,
            value: _cdnEnabled,
            enabled: !_isSaving,
            onChanged: _onCdnEnabledChanged,
          ),
          const SizedBox(height: SpotSpacing.sm),
          _ToggleRow(
            label: l10n.cdnUploadLabel,
            description: l10n.cdnUploadDescription,
            value: _cdnUploadEnabled,
            enabled: !_isSaving && _cdnEnabled,
            onChanged: _onCdnUploadChanged,
          ),
        ],
      ),
    );
  }
}

class _ToggleRow extends StatelessWidget {
  const _ToggleRow({
    required this.label,
    required this.description,
    required this.value,
    required this.enabled,
    required this.onChanged,
  });

  final String label;
  final String description;
  final bool value;
  final bool enabled;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: SpotSpacing.lg,
        vertical: SpotSpacing.md,
      ),
      decoration: SpotDecoration.cardBordered(),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: SpotType.body),
                const SizedBox(height: 4),
                Text(
                  description,
                  style: SpotType.caption.copyWith(
                    color: SpotColors.textTertiary,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: SpotSpacing.md),
          CupertinoSwitch(
            value: value,
            activeTrackColor: SpotColors.accent,
            onChanged: enabled ? onChanged : null,
          ),
        ],
      ),
    );
  }
}

class _PolicyOptionCard extends StatelessWidget {
  const _PolicyOptionCard({
    required this.policy,
    required this.selected,
    required this.enabled,
    required this.onTap,
    required this.l10n,
  });

  final AssetTransportPolicy policy;
  final bool selected;
  final bool enabled;
  final VoidCallback onTap;
  final AppLocalizations l10n;

  String get _localizedLabel => switch (policy) {
    AssetTransportPolicy.always => l10n.alwaysOption,
    AssetTransportPolicy.wifiOnly => l10n.wifiOnlyOption,
    AssetTransportPolicy.off => l10n.offOption,
  };

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: enabled ? onTap : null,
      borderRadius: BorderRadius.circular(SpotRadius.md),
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: SpotSpacing.lg,
          vertical: SpotSpacing.md,
        ),
        decoration: SpotDecoration.cardBordered(),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(_localizedLabel, style: SpotType.body),
                  const SizedBox(height: 4),
                  Text(
                    policy.description,
                    style: SpotType.caption.copyWith(
                      color: SpotColors.textTertiary,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: SpotSpacing.md),
            selected
                ? const Icon(
                    CupertinoIcons.check_mark_circled_solid,
                    color: SpotColors.accent,
                    size: 20,
                  )
                : const Icon(
                    CupertinoIcons.circle,
                    color: SpotColors.textTertiary,
                    size: 20,
                  ),
          ],
        ),
      ),
    );
  }
}
