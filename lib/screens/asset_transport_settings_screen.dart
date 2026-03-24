import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import 'package:mobile/features/p2p/p2p_service.dart';
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
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _selectedPolicy = UserPrefsService.instance.assetTransportPolicy;
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: SpotColors.bg,
      appBar: AppBar(
        backgroundColor: SpotColors.bg,
        title: const Text('Asset Transport', style: SpotType.subheading),
      ),
      body: ListView(
        padding: const EdgeInsets.symmetric(
          horizontal: SpotSpacing.lg,
          vertical: SpotSpacing.lg,
        ),
        children: [
          Text(
            'Control when Spot can share and fetch full images and videos over peer transport to avoid unexpected mobile-data use.',
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
            ),
            if (policy != AssetTransportPolicy.values.last)
              const SizedBox(height: SpotSpacing.sm),
          ],
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
  });

  final AssetTransportPolicy policy;
  final bool selected;
  final bool enabled;
  final VoidCallback onTap;

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
                  Text(policy.label, style: SpotType.body),
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
