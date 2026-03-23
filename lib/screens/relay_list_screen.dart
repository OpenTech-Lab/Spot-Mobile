import 'package:flutter/material.dart';

import 'package:mobile/features/nostr/nostr_service.dart';
import 'package:mobile/theme/spot_theme.dart';

class RelayListScreen extends StatelessWidget {
  const RelayListScreen({super.key, required this.nostrService});

  final NostrService nostrService;

  @override
  Widget build(BuildContext context) {
    final allRelays = nostrService.relayUrls;
    final connected = nostrService.connectedRelays.toSet();

    return Scaffold(
      backgroundColor: SpotColors.bg,
      appBar: AppBar(
        backgroundColor: SpotColors.bg,
        title: const Text('Relay List', style: SpotType.subheading),
      ),
      body: ListView.separated(
        padding: const EdgeInsets.all(SpotSpacing.lg),
        itemCount: allRelays.length,
        separatorBuilder: (_, __) => const SizedBox(height: SpotSpacing.sm),
        itemBuilder: (context, index) {
          final url = allRelays[index];
          final isConnected = connected.contains(url);
          return _RelayRow(url: url, isConnected: isConnected);
        },
      ),
    );
  }
}

class _RelayRow extends StatelessWidget {
  const _RelayRow({required this.url, required this.isConnected});

  final String url;
  final bool isConnected;

  @override
  Widget build(BuildContext context) {
    final statusColor =
        isConnected ? SpotColors.success : SpotColors.textTertiary;

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: SpotSpacing.lg,
        vertical: SpotSpacing.md,
      ),
      decoration: SpotDecoration.cardBordered(),
      child: Row(
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              color: statusColor,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: SpotSpacing.md),
          Expanded(
            child: Text(
              url,
              style: SpotType.mono.copyWith(
                color: SpotColors.textPrimary,
                fontSize: 12,
              ),
            ),
          ),
          const SizedBox(width: SpotSpacing.sm),
          Text(
            isConnected ? 'Connected' : 'Disconnected',
            style: SpotType.caption.copyWith(color: statusColor),
          ),
        ],
      ),
    );
  }
}
