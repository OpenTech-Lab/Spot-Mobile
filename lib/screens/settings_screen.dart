import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import 'package:mobile/features/nostr/nostr_service.dart';
import 'package:mobile/models/wallet_model.dart';
import 'package:mobile/screens/relay_list_screen.dart';
import 'package:mobile/screens/wallet_screen.dart';
import 'package:mobile/theme/spot_theme.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({
    super.key,
    required this.wallet,
    required this.nostrService,
  });

  final WalletModel wallet;
  final NostrService nostrService;

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
                builder: (_) => RelayListScreen(nostrService: nostrService),
              ),
            ),
          ),
          const SizedBox(height: SpotSpacing.sm),
          _SettingsRow(
            icon: CupertinoIcons.person_crop_circle,
            label: 'Identity',
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => WalletScreen(wallet: wallet),
              ),
            ),
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
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

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
            Expanded(
              child: Text(label, style: SpotType.body),
            ),
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
