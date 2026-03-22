import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';

import 'package:mobile/core/wallet.dart';
import 'package:mobile/models/wallet_model.dart';
import 'package:mobile/screens/home_screen.dart';
import 'package:mobile/services/storage_service.dart';

/// Three-step onboarding flow:
///   Step 0 — Welcome
///   Step 1 — Create or import identity
///   Step 2 — Success (shows npub + QR)
class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  int _step = 0;

  // Step 1 state
  bool _isImporting = false;
  bool _isLoading = false;
  String _importError = '';
  final _importController = TextEditingController();

  // Created/imported wallet
  WalletModel? _wallet;
  bool _mnemonicConfirmed = false;
  bool _mnemonicRevealed = false;

  @override
  void dispose() {
    _importController.dispose();
    super.dispose();
  }

  // ── Actions ───────────────────────────────────────────────────────────────

  Future<void> _createWallet() async {
    setState(() {
      _isLoading = true;
      _isImporting = false;
      _importError = '';
    });

    try {
      final wallet = await WalletService.createNewWallet();
      await StorageService.instance.saveWallet(wallet);
      if (mounted) {
        setState(() {
          _wallet = wallet;
          _step = 2;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _importError = 'Failed to create wallet: $e';
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _importWallet() async {
    final text = _importController.text.trim();
    final words = text.split(RegExp(r'\s+'));

    if (words.length != 12) {
      setState(() => _importError = 'Please enter exactly 12 mnemonic words.');
      return;
    }

    setState(() {
      _isLoading = true;
      _importError = '';
    });

    try {
      final wallet = await WalletService.importFromMnemonic(words);
      await StorageService.instance.saveWallet(wallet);
      if (mounted) {
        setState(() {
          _wallet = wallet;
          _step = 2;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _importError = 'Invalid mnemonic: $e';
          _isLoading = false;
        });
      }
    }
  }

  void _goToHome() {
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (_) => HomeScreen(wallet: _wallet!),
      ),
    );
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0D0D0D),
      body: SafeArea(
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 300),
          child: switch (_step) {
            0 => _WelcomeStep(
                key: const ValueKey(0),
                onNext: () => setState(() => _step = 1),
              ),
            1 => _IdentityStep(
                key: const ValueKey(1),
                isImporting: _isImporting,
                isLoading: _isLoading,
                importError: _importError,
                importController: _importController,
                onCreateTap: _createWallet,
                onImportToggle: () =>
                    setState(() => _isImporting = !_isImporting),
                onImportSubmit: _importWallet,
              ),
            _ => _SuccessStep(
                key: const ValueKey(2),
                wallet: _wallet!,
                mnemonicRevealed: _mnemonicRevealed,
                mnemonicConfirmed: _mnemonicConfirmed,
                onRevealMnemonic: () =>
                    setState(() => _mnemonicRevealed = true),
                onConfirm: () => setState(() => _mnemonicConfirmed = true),
                onEnter: _goToHome,
              ),
          },
        ),
      ),
    );
  }
}

// ── Step 0: Welcome ───────────────────────────────────────────────────────────

class _WelcomeStep extends StatelessWidget {
  const _WelcomeStep({super.key, required this.onNext});

  final VoidCallback onNext;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.radio_button_checked,
              color: Color(0xFFFF4444), size: 80),
          const SizedBox(height: 24),
          const Text(
            'SPOT',
            style: TextStyle(
              color: Color(0xFFFF4444),
              fontSize: 42,
              fontWeight: FontWeight.bold,
              letterSpacing: 8,
              fontFamily: 'monospace',
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Citizen Swarm',
            style: TextStyle(color: Colors.white54, fontSize: 16),
          ),
          const SizedBox(height: 32),
          const Text(
            'A decentralized, geo-tagged media platform.\n'
            'Record, publish, and protect — with zero central servers.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.white70, height: 1.5),
          ),
          const SizedBox(height: 16),
          const _FeatureBullet(icon: Icons.lock, text: 'Device-bound identity (Nostr wallet)'),
          const _FeatureBullet(icon: Icons.gps_fixed, text: 'GPS-locked media at capture time'),
          const _FeatureBullet(icon: Icons.shield, text: 'Danger Mode: face blur + GPS strip'),
          const _FeatureBullet(icon: Icons.share, text: 'P2P media swarm — no central servers'),
          const SizedBox(height: 48),
          FilledButton(
            onPressed: onNext,
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFFFF4444),
              minimumSize: const Size(double.infinity, 52),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
            ),
            child: const Text('Get Started',
                style:
                    TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }
}

class _FeatureBullet extends StatelessWidget {
  const _FeatureBullet({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Icon(icon, color: const Color(0xFFFF4444), size: 18),
          const SizedBox(width: 10),
          Expanded(
              child: Text(text,
                  style: const TextStyle(color: Colors.white70))),
        ],
      ),
    );
  }
}

// ── Step 1: Identity ──────────────────────────────────────────────────────────

class _IdentityStep extends StatelessWidget {
  const _IdentityStep({
    super.key,
    required this.isImporting,
    required this.isLoading,
    required this.importError,
    required this.importController,
    required this.onCreateTap,
    required this.onImportToggle,
    required this.onImportSubmit,
  });

  final bool isImporting;
  final bool isLoading;
  final String importError;
  final TextEditingController importController;
  final VoidCallback onCreateTap;
  final VoidCallback onImportToggle;
  final VoidCallback onImportSubmit;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'Your Identity',
            style: TextStyle(
              color: Colors.white,
              fontSize: 28,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Your identity is a cryptographic wallet bound to this device. '
            'You can migrate it to a new phone anytime using your mnemonic.',
            style: TextStyle(color: Colors.white54, height: 1.5),
          ),
          const SizedBox(height: 40),

          if (!isImporting) ...[
            FilledButton.icon(
              onPressed: isLoading ? null : onCreateTap,
              icon: isLoading
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                          color: Colors.white, strokeWidth: 2))
                  : const Icon(Icons.add),
              label: const Text('Create New Identity'),
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFFFF4444),
                minimumSize: const Size(double.infinity, 52),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
            ),
            const SizedBox(height: 16),
            OutlinedButton.icon(
              onPressed: onImportToggle,
              icon: const Icon(Icons.file_download_outlined),
              label: const Text('Import Existing Identity'),
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.white70,
                side: const BorderSide(color: Colors.white24),
                minimumSize: const Size(double.infinity, 52),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ] else ...[
            const Text(
              'Enter your 12-word mnemonic:',
              style: TextStyle(color: Colors.white70),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: importController,
              maxLines: 4,
              style: const TextStyle(
                  color: Colors.white, fontFamily: 'monospace'),
              decoration: InputDecoration(
                hintText: 'word1 word2 word3 ...',
                hintStyle: const TextStyle(color: Colors.white24),
                filled: true,
                fillColor: const Color(0xFF1A1A1A),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
            if (importError.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(importError,
                  style: const TextStyle(
                      color: Color(0xFFFF4444), fontSize: 13)),
            ],
            const SizedBox(height: 16),
            FilledButton(
              onPressed: isLoading ? null : onImportSubmit,
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFFFF4444),
                minimumSize: const Size(double.infinity, 52),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
              child: isLoading
                  ? const CircularProgressIndicator(color: Colors.white)
                  : const Text('Import Identity'),
            ),
            const SizedBox(height: 12),
            TextButton(
              onPressed: onImportToggle,
              child: const Text('Back',
                  style: TextStyle(color: Colors.white54)),
            ),
          ],
        ],
      ),
    );
  }
}

// ── Step 2: Success ───────────────────────────────────────────────────────────

class _SuccessStep extends StatelessWidget {
  const _SuccessStep({
    super.key,
    required this.wallet,
    required this.mnemonicRevealed,
    required this.mnemonicConfirmed,
    required this.onRevealMnemonic,
    required this.onConfirm,
    required this.onEnter,
  });

  final WalletModel wallet;
  final bool mnemonicRevealed;
  final bool mnemonicConfirmed;
  final VoidCallback onRevealMnemonic;
  final VoidCallback onConfirm;
  final VoidCallback onEnter;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 24),
          const Icon(Icons.check_circle,
              color: Colors.greenAccent, size: 64),
          const SizedBox(height: 16),
          const Text(
            'Identity Created!',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Colors.white,
              fontSize: 24,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Your Nostr public key (npub):',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.white54),
          ),
          const SizedBox(height: 8),
          GestureDetector(
            onTap: () {
              Clipboard.setData(ClipboardData(text: wallet.npub));
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('npub copied')),
              );
            },
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFF1A1A1A),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                wallet.npub,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Color(0xFFFF4444),
                  fontFamily: 'monospace',
                  fontSize: 11,
                ),
              ),
            ),
          ),
          const SizedBox(height: 16),
          // QR code of npub
          Center(
            child: QrImageView(
              data: wallet.npub,
              version: QrVersions.auto,
              size: 160,
              backgroundColor: Colors.white,
            ),
          ),
          const SizedBox(height: 24),

          // Mnemonic backup section
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFF1A1A1A),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFFFF4444), width: 1),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Row(
                  children: [
                    Icon(Icons.warning, color: Color(0xFFFF4444), size: 18),
                    SizedBox(width: 8),
                    Text(
                      'BACK UP YOUR MNEMONIC',
                      style: TextStyle(
                          color: Color(0xFFFF4444),
                          fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                const Text(
                  'These 12 words are the ONLY way to recover your identity '
                  'if you lose your phone. Write them down on paper and store '
                  'them safely.',
                  style: TextStyle(color: Colors.white70, fontSize: 12),
                ),
                const SizedBox(height: 12),
                if (!mnemonicRevealed)
                  Center(
                    child: TextButton(
                      onPressed: onRevealMnemonic,
                      child: const Text('Reveal Mnemonic',
                          style:
                              TextStyle(color: Color(0xFFFF4444))),
                    ),
                  )
                else ...[
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: wallet.mnemonic.asMap().entries.map((e) {
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
                            fontSize: 13,
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 12),
                  if (!mnemonicConfirmed)
                    FilledButton(
                      onPressed: onConfirm,
                      style: FilledButton.styleFrom(
                        backgroundColor: Colors.green.shade700,
                        minimumSize: const Size(double.infinity, 44),
                      ),
                      child: const Text("I've written it down"),
                    ),
                ],
              ],
            ),
          ),

          const SizedBox(height: 24),
          FilledButton(
            onPressed: mnemonicConfirmed || !mnemonicRevealed ? onEnter : null,
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFFFF4444),
              minimumSize: const Size(double.infinity, 52),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
              disabledBackgroundColor: Colors.grey.shade800,
            ),
            child: Text(
              mnemonicRevealed && !mnemonicConfirmed
                  ? 'Confirm backup first'
                  : 'Enter Spot',
              style: const TextStyle(
                  fontSize: 16, fontWeight: FontWeight.bold),
            ),
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }
}
