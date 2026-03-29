import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';

import 'package:mobile/core/wallet.dart';
import 'package:mobile/models/wallet_model.dart';
import 'package:mobile/screens/home_screen.dart';
import 'package:mobile/services/storage_service.dart';
import 'package:mobile/theme/spot_theme.dart';

/// Three-step onboarding:  Welcome → Identity → Success
class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  int _step = 0;

  bool _isImporting = false;
  bool _isLoading   = false;
  String _importError = '';
  final _importController = TextEditingController();

  WalletModel? _wallet;
  bool _mnemonicRevealed  = false;
  bool _mnemonicConfirmed = false;

  @override
  void dispose() {
    _importController.dispose();
    super.dispose();
  }

  Future<void> _createWallet() async {
    setState(() { _isLoading = true; _importError = ''; });
    try {
      final wallet = await WalletService.createNewWallet();
      await StorageService.instance.saveWallet(wallet);
      if (mounted) setState(() { _wallet = wallet; _step = 2; _isLoading = false; });
    } catch (e) {
      if (mounted) setState(() { _importError = 'Failed: $e'; _isLoading = false; });
    }
  }

  Future<void> _importWallet() async {
    final words = _importController.text.trim().split(RegExp(r'\s+'));
    if (words.length != 12) {
      setState(() => _importError = 'Enter exactly 12 recovery words.');
      return;
    }
    setState(() { _isLoading = true; _importError = ''; });
    try {
      final wallet = await WalletService.importFromMnemonic(words);
      await StorageService.instance.saveWallet(wallet);
      if (mounted) setState(() { _wallet = wallet; _step = 2; _isLoading = false; });
    } catch (e) {
      if (mounted) setState(() { _importError = 'Invalid phrase: $e'; _isLoading = false; });
    }
  }

  void _goToHome() => Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => HomeScreen(wallet: _wallet!)),
      );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: SpotColors.bg,
      body: SafeArea(
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 260),
          transitionBuilder: (child, anim) => FadeTransition(opacity: anim, child: child),
          child: switch (_step) {
            0 => _WelcomeStep(key: const ValueKey(0), onNext: () => setState(() => _step = 1)),
            1 => _IdentityStep(
                key: const ValueKey(1),
                isImporting:      _isImporting,
                isLoading:        _isLoading,
                importError:      _importError,
                importController: _importController,
                onCreateTap:      _createWallet,
                onImportToggle:   () => setState(() => _isImporting = !_isImporting),
                onImportSubmit:   _importWallet,
              ),
            _ => _SuccessStep(
                key: const ValueKey(2),
                wallet:            _wallet!,
                mnemonicRevealed:  _mnemonicRevealed,
                mnemonicConfirmed: _mnemonicConfirmed,
                onRevealMnemonic:  () => setState(() => _mnemonicRevealed = true),
                onConfirm:         () => setState(() => _mnemonicConfirmed = true),
                onEnter:           _goToHome,
              ),
          },
        ),
      ),
    );
  }
}

// ── Welcome ────────────────────────────────────────────────────────────────────

class _WelcomeStep extends StatelessWidget {
  const _WelcomeStep({super.key, required this.onNext});
  final VoidCallback onNext;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: SpotSpacing.xxl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Spacer(flex: 3),

          const Text('Spot', style: SpotType.wordmark),
          const SizedBox(height: SpotSpacing.sm),
          Container(width: 28, height: 0.5, color: SpotColors.accent),
          const SizedBox(height: SpotSpacing.lg),
          Text(
            'Decentralised media.\nVerified at capture.',
            style: SpotType.bodySecondary.copyWith(
              fontSize: 15,
              fontWeight: FontWeight.w300,
            ),
          ),

          const Spacer(flex: 2),

          const _Bullet('Device-bound cryptographic identity'),
          const _Bullet('GPS-locked at the moment of capture'),
          const _Bullet('Danger mode — blur faces in photos, hide location'),
          const _Bullet('Peer-to-peer, no central servers'),

          const Spacer(flex: 3),

          _PrimaryBtn(label: 'Get started', onPressed: onNext),
          const SizedBox(height: SpotSpacing.xxl),
        ],
      ),
    );
  }
}

class _Bullet extends StatelessWidget {
  const _Bullet(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: [
          Container(
            width: 3,
            height: 3,
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              color: SpotColors.accent,
            ),
          ),
          const SizedBox(width: SpotSpacing.md),
          Text(text, style: SpotType.bodySecondary),
        ],
      ),
    );
  }
}

// ── Identity ───────────────────────────────────────────────────────────────────

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
      padding: const EdgeInsets.symmetric(horizontal: SpotSpacing.xxl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Spacer(flex: 2),

          Text(
            isImporting ? 'Import identity' : 'Create identity',
            style: SpotType.heading,
          ),
          const SizedBox(height: SpotSpacing.sm),
          Text(
            isImporting
                ? 'Enter your 12-word recovery phrase.'
                : 'A keypair will be generated and stored securely on this device.',
            style: SpotType.bodySecondary,
          ),

          const Spacer(flex: 1),

          if (!isImporting) ...[
            _PrimaryBtn(
              label: 'Generate new identity',
              onPressed: isLoading ? null : onCreateTap,
              loading: isLoading,
            ),
            const SizedBox(height: SpotSpacing.md),
            _OutlineBtn(label: 'Import existing', onPressed: onImportToggle),
          ] else ...[
            TextField(
              controller: importController,
              maxLines: 4,
              style: SpotType.body,
              decoration: InputDecoration(
                hintText: 'word1 word2 word3 …',
                hintStyle: SpotType.bodySecondary.copyWith(color: SpotColors.textTertiary),
                filled: true,
                fillColor: SpotColors.surface,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(SpotRadius.sm),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
            if (importError.isNotEmpty) ...[
              const SizedBox(height: SpotSpacing.sm),
              Text(
                importError,
                style: SpotType.caption.copyWith(color: SpotColors.danger),
              ),
            ],
            const SizedBox(height: SpotSpacing.lg),
            _PrimaryBtn(
              label: 'Import identity',
              onPressed: isLoading ? null : onImportSubmit,
              loading: isLoading,
            ),
            const SizedBox(height: SpotSpacing.sm),
            TextButton(
              onPressed: onImportToggle,
              child: Text('Back', style: SpotType.bodySecondary),
            ),
          ],

          const Spacer(flex: 2),
        ],
      ),
    );
  }
}

// ── Success ────────────────────────────────────────────────────────────────────

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
      padding: const EdgeInsets.fromLTRB(
        SpotSpacing.xxl, SpotSpacing.xxxl,
        SpotSpacing.xxl, SpotSpacing.xxl,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text('Identity ready', style: SpotType.heading),
          const SizedBox(height: SpotSpacing.xs),
          const Text('Your public key', style: SpotType.bodySecondary),
          const SizedBox(height: SpotSpacing.md),

          // npub row
          GestureDetector(
            onTap: () {
              Clipboard.setData(ClipboardData(text: wallet.npub));
              ScaffoldMessenger.of(context)
                  .showSnackBar(const SnackBar(content: Text('Copied')));
            },
            child: Container(
              padding: const EdgeInsets.all(SpotSpacing.md),
              decoration: SpotDecoration.card(),
              child: Row(
                children: [
                  Expanded(
                    child: Text(wallet.npub, style: SpotType.mono, overflow: TextOverflow.fade),
                  ),
                  const SizedBox(width: SpotSpacing.sm),
                  const Icon(CupertinoIcons.doc_on_doc, color: SpotColors.textTertiary, size: 13),
                ],
              ),
            ),
          ),

          const SizedBox(height: SpotSpacing.xl),
          Center(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(SpotRadius.sm),
              child: QrImageView(
                data: wallet.npub,
                version: QrVersions.auto,
                size: 130,
                backgroundColor: Colors.white,
              ),
            ),
          ),

          const SizedBox(height: SpotSpacing.xxl),

          // Recovery phrase
          Container(
            padding: const EdgeInsets.all(SpotSpacing.lg),
            decoration: SpotDecoration.cardBordered(),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Recovery phrase', style: SpotType.body),
                const SizedBox(height: SpotSpacing.xs),
                const Text(
                  'The only way to restore your identity if you lose this device. '
                  'Write these down and keep them safe.',
                  style: SpotType.bodySecondary,
                ),
                const SizedBox(height: SpotSpacing.lg),
                if (!mnemonicRevealed)
                  Center(
                    child: TextButton(
                      onPressed: onRevealMnemonic,
                      child: const Text('Show recovery phrase'),
                    ),
                  )
                else ...[
                  Wrap(
                    spacing: SpotSpacing.xs,
                    runSpacing: SpotSpacing.xs,
                    children: wallet.mnemonic.asMap().entries.map((e) {
                      return Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: SpotSpacing.sm,
                          vertical: 5,
                        ),
                        decoration: BoxDecoration(
                          color: SpotColors.surfaceHigh,
                          borderRadius: BorderRadius.circular(SpotRadius.xs),
                        ),
                        child: Text(
                          '${e.key + 1}. ${e.value}',
                          style: SpotType.mono.copyWith(color: SpotColors.textPrimary),
                        ),
                      );
                    }).toList(),
                  ),
                  if (!mnemonicConfirmed) ...[
                    const SizedBox(height: SpotSpacing.lg),
                    _OutlineBtn(
                      label: 'I have saved these words',
                      onPressed: onConfirm,
                    ),
                  ],
                ],
              ],
            ),
          ),

          const SizedBox(height: SpotSpacing.xl),
          _PrimaryBtn(
            label: mnemonicRevealed && !mnemonicConfirmed
                ? 'Confirm backup first'
                : 'Continue',
            onPressed: mnemonicConfirmed || !mnemonicRevealed ? onEnter : null,
          ),
        ],
      ),
    );
  }
}

// ── Shared button components ───────────────────────────────────────────────────

class _PrimaryBtn extends StatelessWidget {
  const _PrimaryBtn({required this.label, required this.onPressed, this.loading = false});
  final String label;
  final VoidCallback? onPressed;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: FilledButton(
        onPressed: onPressed,
        style: FilledButton.styleFrom(
          padding: const EdgeInsets.symmetric(vertical: SpotSpacing.md),
        ),
        child: loading
            ? const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(
                  color: SpotColors.onAccent,
                  strokeWidth: 1.5,
                ),
              )
            : Text(label),
      ),
    );
  }
}

class _OutlineBtn extends StatelessWidget {
  const _OutlineBtn({required this.label, required this.onPressed});
  final String label;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: OutlinedButton(
        onPressed: onPressed,
        style: OutlinedButton.styleFrom(
          padding: const EdgeInsets.symmetric(vertical: SpotSpacing.md),
        ),
        child: Text(label),
      ),
    );
  }
}
