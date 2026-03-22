import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';

import 'package:mobile/core/wallet.dart';
import 'package:mobile/models/wallet_model.dart';

/// Wallet / Identity screen.
///
/// Shows:
/// - Generated avatar (colour grid derived from pubkey)
/// - npub (truncated + copy)
/// - Device ID
/// - Mnemonic (hidden by default, reveal button)
/// - "Migrate Identity" button with encrypted QR
/// - Revocation status
class WalletScreen extends StatefulWidget {
  const WalletScreen({super.key, required this.wallet});

  final WalletModel wallet;

  @override
  State<WalletScreen> createState() => _WalletScreenState();
}

class _WalletScreenState extends State<WalletScreen> {
  bool _mnemonicVisible = false;
  bool _migrationQrVisible = false;
  bool _isGeneratingQr = false;
  String? _migrationPayload;

  Future<void> _revealMnemonic() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A1A),
        title: const Text('Reveal Secret Words',
            style: TextStyle(color: Colors.white)),
        content: const Text(
          'Your mnemonic is the ONLY recovery backup for your identity. '
          'Never share it with anyone.',
          style: TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel',
                style: TextStyle(color: Colors.white54)),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Reveal',
                style: TextStyle(color: Color(0xFFFF4444))),
          ),
        ],
      ),
    );
    if (confirmed == true && mounted) {
      setState(() => _mnemonicVisible = true);
    }
  }

  Future<void> _showMigrationQr() async {
    setState(() => _isGeneratingQr = true);
    try {
      final payload =
          await WalletService.createMigrationPayload(widget.wallet);
      if (mounted) {
        setState(() {
          _migrationPayload = payload;
          _migrationQrVisible = true;
          _isGeneratingQr = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isGeneratingQr = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to generate QR: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final wallet = widget.wallet;

    return Scaffold(
      backgroundColor: const Color(0xFF0D0D0D),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0D0D0D),
        foregroundColor: Colors.white,
        title: const Text('Identity & Wallet',
            style: TextStyle(fontWeight: FontWeight.bold)),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // ── Revocation banner ─────────────────────────────────────────
            if (wallet.isRevoked)
              Container(
                padding: const EdgeInsets.all(12),
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                  color: Colors.orange.shade900.withOpacity(0.3),
                  borderRadius: BorderRadius.circular(10),
                  border:
                      Border.all(color: Colors.orange.shade700, width: 1),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.warning, color: Colors.orange, size: 18),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'This wallet has been revoked (migrated to a new device). '
                        'Sign in with your new device.',
                        style: TextStyle(
                            color: Colors.orange, fontSize: 12),
                      ),
                    ),
                  ],
                ),
              ),

            // ── Avatar + pubkey ───────────────────────────────────────────
            Center(
              child: _PubkeyAvatar(pubkeyHex: wallet.publicKeyHex),
            ),
            const SizedBox(height: 16),
            const Center(
              child: Text('Your Nostr Public Key',
                  style: TextStyle(color: Colors.white54, fontSize: 12)),
            ),
            const SizedBox(height: 4),
            GestureDetector(
              onTap: () {
                Clipboard.setData(ClipboardData(text: wallet.npub));
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('npub copied to clipboard')),
                );
              },
              child: Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: const Color(0xFF1A1A1A),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        wallet.npub,
                        style: const TextStyle(
                          color: Color(0xFFFF4444),
                          fontFamily: 'monospace',
                          fontSize: 11,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const Icon(Icons.copy,
                        color: Colors.white30, size: 16),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 16),

            // ── Device ID ─────────────────────────────────────────────────
            _InfoRow(
              label: 'Device ID',
              value: wallet.deviceId.length > 20
                  ? '${wallet.deviceId.substring(0, 12)}...'
                  : wallet.deviceId,
              icon: Icons.smartphone,
            ),
            _InfoRow(
              label: 'Created',
              value: wallet.createdAt.toLocal().toString().substring(0, 16),
              icon: Icons.calendar_today,
            ),

            const SizedBox(height: 24),

            // ── Mnemonic section ──────────────────────────────────────────
            _SectionCard(
              title: 'Secret Recovery Words',
              icon: Icons.vpn_key,
              iconColor: const Color(0xFFFF4444),
              child: _mnemonicVisible
                  ? Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Never share these words with anyone.',
                          style: TextStyle(
                              color: Colors.white54, fontSize: 12),
                        ),
                        const SizedBox(height: 10),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children:
                              wallet.mnemonic.asMap().entries.map((e) {
                            return Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 10, vertical: 6),
                              decoration: BoxDecoration(
                                color: const Color(0xFF0D0D0D),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                '${e.key + 1}. ${e.value}',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontFamily: 'monospace',
                                  fontSize: 12,
                                ),
                              ),
                            );
                          }).toList(),
                        ),
                      ],
                    )
                  : Center(
                      child: TextButton.icon(
                        onPressed: _revealMnemonic,
                        icon: const Icon(Icons.visibility_off,
                            color: Color(0xFFFF4444)),
                        label: const Text('Reveal Recovery Words',
                            style:
                                TextStyle(color: Color(0xFFFF4444))),
                      ),
                    ),
            ),

            const SizedBox(height: 16),

            // ── Migration section ─────────────────────────────────────────
            _SectionCard(
              title: 'Migrate to New Device',
              icon: Icons.qr_code,
              iconColor: Colors.white70,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text(
                    '1. Tap "Generate Migration QR" on this phone.\n'
                    '2. On your new phone, open Spot and choose "Import".\n'
                    '3. Scan the QR code. Your identity will transfer.\n'
                    '4. This device will be revoked automatically.',
                    style:
                        TextStyle(color: Colors.white54, fontSize: 12, height: 1.6),
                  ),
                  const SizedBox(height: 12),
                  if (!_migrationQrVisible)
                    FilledButton.icon(
                      onPressed:
                          wallet.isRevoked || _isGeneratingQr
                              ? null
                              : _showMigrationQr,
                      icon: _isGeneratingQr
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2, color: Colors.white))
                          : const Icon(Icons.qr_code),
                      label: const Text('Generate Migration QR'),
                      style: FilledButton.styleFrom(
                        backgroundColor: const Color(0xFF2A2A2A),
                      ),
                    )
                  else if (_migrationPayload != null) ...[
                    Center(
                      child: QrImageView(
                        data: _migrationPayload!,
                        version: QrVersions.auto,
                        size: 200,
                        backgroundColor: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'This QR contains your encrypted identity. '
                      'Scan it with your new device.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                          color: Colors.white54, fontSize: 11),
                    ),
                    const SizedBox(height: 8),
                    TextButton(
                      onPressed: () =>
                          setState(() => _migrationQrVisible = false),
                      child: const Text('Hide QR',
                          style: TextStyle(color: Colors.white38)),
                    ),
                  ],
                ],
              ),
            ),

            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }
}

// ── Subwidgets ────────────────────────────────────────────────────────────────

class _PubkeyAvatar extends StatelessWidget {
  const _PubkeyAvatar({required this.pubkeyHex});

  final String pubkeyHex;

  @override
  Widget build(BuildContext context) {
    // Use a consistent accent colour from first byte
    final accentHex = pubkeyHex.substring(0, 6);
    final accentValue =
        int.tryParse(accentHex, radix: 16) ?? 0xFF4444;
    final accent = Color(0xFF000000 | accentValue);

    return Container(
      width: 80,
      height: 80,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: accent, width: 3),
        gradient: RadialGradient(
          colors: [accent.withOpacity(0.4), const Color(0xFF0D0D0D)],
        ),
      ),
      child: Center(
        child: Text(
          pubkeyHex.substring(0, 2).toUpperCase(),
          style: TextStyle(
            color: accent,
            fontSize: 28,
            fontWeight: FontWeight.bold,
            fontFamily: 'monospace',
          ),
        ),
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow(
      {required this.label, required this.value, required this.icon});

  final String label;
  final String value;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Icon(icon, color: Colors.white30, size: 16),
          const SizedBox(width: 8),
          Text('$label: ',
              style:
                  const TextStyle(color: Colors.white54, fontSize: 13)),
          Expanded(
            child: Text(value,
                style:
                    const TextStyle(color: Colors.white70, fontSize: 13),
                overflow: TextOverflow.ellipsis),
          ),
        ],
      ),
    );
  }
}

class _SectionCard extends StatelessWidget {
  const _SectionCard({
    required this.title,
    required this.icon,
    required this.iconColor,
    required this.child,
  });

  final String title;
  final IconData icon;
  final Color iconColor;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A1A),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF2A2A2A)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: iconColor, size: 16),
              const SizedBox(width: 8),
              Text(
                title,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }
}
