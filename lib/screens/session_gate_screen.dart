import 'dart:async';

import 'package:flutter/material.dart';

import 'package:mobile/core/community_safety.dart';
import 'package:mobile/core/wallet.dart';
import 'package:mobile/l10n/app_localizations.dart';
import 'package:mobile/models/wallet_model.dart';
import 'package:mobile/screens/altcha_gate_screen.dart';
import 'package:mobile/screens/onboarding_screen.dart';
import 'package:mobile/screens/splash_screen.dart';
import 'package:mobile/services/app_lock_service.dart';
import 'package:mobile/services/session_logout_service.dart';
import 'package:mobile/services/user_prefs_service.dart';
import 'package:mobile/theme/spot_theme.dart';
import 'package:mobile/widgets/app_loading_view.dart';
import 'package:mobile/widgets/ugc_terms_gate.dart';

typedef SessionUnlockedBuilder = Widget Function(WalletModel wallet);
typedef SessionOnboardingBuilder = Widget Function();
typedef SessionLogoutRunner = Future<void> Function();

List<String> normalizeRecoveryPhraseWords(String phrase) {
  return phrase
      .trim()
      .toLowerCase()
      .split(RegExp(r'\s+'))
      .where((word) => word.isNotEmpty)
      .toList(growable: false);
}

String? validateRecoveryPhraseForWallet(WalletModel wallet, String phrase) {
  final words = normalizeRecoveryPhraseWords(phrase);
  if (words.length != 12 || !WalletService.validateMnemonic(words)) {
    return 'Enter the exact 12-word recovery phrase.';
  }

  final (_, derivedPubkey) = WalletService.keypairFromMnemonic(words);
  if (derivedPubkey != wallet.publicKeyHex) {
    return 'Recovery phrase does not match this saved account.';
  }

  return null;
}

class SessionGateScreen extends StatefulWidget {
  const SessionGateScreen({
    super.key,
    this.initialWallet,
    this.appLockService,
    this.logoutRunner,
    this.unlockedBuilder,
    this.onboardingBuilder,
    this.safeModeEnabled,
    this.relockAfter = const Duration(minutes: 2),
    this.hasAcceptedTerms,
    this.acceptTerms,
  });

  final WalletModel? initialWallet;
  final AppLockService? appLockService;
  final SessionLogoutRunner? logoutRunner;
  final SessionUnlockedBuilder? unlockedBuilder;
  final SessionOnboardingBuilder? onboardingBuilder;
  final bool? safeModeEnabled;
  final Duration relockAfter;
  final bool Function(String version)? hasAcceptedTerms;
  final Future<void> Function(String version)? acceptTerms;

  @override
  State<SessionGateScreen> createState() => _SessionGateScreenState();
}

class _SessionGateScreenState extends State<SessionGateScreen>
    with WidgetsBindingObserver {
  WalletModel? _wallet;
  AppLockStatus? _lockStatus;
  bool _isLocked = false;
  bool _isCheckingLock = false;
  bool _isUnlocking = false;
  String? _unlockError;
  DateTime? _backgroundedAt;

  AppLockService get _appLockService =>
      widget.appLockService ?? AppLockService.instance;
  SessionLogoutRunner get _logoutRunner =>
      widget.logoutRunner ?? SessionLogoutService.instance.logout;
  bool get _safeModeEnabled =>
      widget.safeModeEnabled ?? UserPrefsService.instance.safeModeEnabled;

  bool _hasAcceptedTerms(String version) {
    return widget.hasAcceptedTerms?.call(version) ??
        UserPrefsService.instance.hasAcceptedUgcTerms(version);
  }

  Future<void> _acceptTerms(String version) async {
    final acceptTerms = widget.acceptTerms;
    if (acceptTerms != null) {
      await acceptTerms(version);
      return;
    }
    await UserPrefsService.instance.acceptUgcTerms(version);
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _wallet = widget.initialWallet;
    _isLocked = _wallet != null && _safeModeEnabled;
    if (_wallet != null && _safeModeEnabled) {
      unawaited(_prepareLock(autoUnlock: true));
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (_wallet == null || !_safeModeEnabled) return;

    switch (state) {
      case AppLifecycleState.inactive:
      case AppLifecycleState.paused:
      case AppLifecycleState.hidden:
        _backgroundedAt ??= DateTime.now();
        break;
      case AppLifecycleState.resumed:
        final backgroundedAt = _backgroundedAt;
        _backgroundedAt = null;
        if (backgroundedAt == null) return;
        if (DateTime.now().difference(backgroundedAt) < widget.relockAfter) {
          return;
        }
        unawaited(_prepareLock(autoUnlock: false));
        break;
      case AppLifecycleState.detached:
        break;
    }
  }

  Future<void> _prepareLock({required bool autoUnlock}) async {
    if (_wallet == null || _isCheckingLock) return;

    setState(() {
      _isLocked = true;
      _isCheckingLock = true;
      _unlockError = null;
    });

    final status = await _appLockService.getStatus();
    if (!mounted) return;

    setState(() {
      _lockStatus = status;
      _isCheckingLock = false;
    });

    if (autoUnlock && status.canAuthenticate) {
      await _unlock(showErrorOnFailure: false);
    }
  }

  Future<void> _unlock({bool showErrorOnFailure = true}) async {
    if (_wallet == null || _isUnlocking) return;
    final status = _lockStatus;
    if (status == null || !status.canAuthenticate) return;

    setState(() {
      _isUnlocking = true;
      _unlockError = null;
    });

    final didUnlock = await _appLockService.authenticate();
    if (!mounted) return;

    setState(() {
      _isUnlocking = false;
      if (didUnlock) {
        _isLocked = false;
        _backgroundedAt = null;
      } else if (showErrorOnFailure) {
        _unlockError = AppLocalizations.of(context)!.unlockCancelledError;
      }
    });
  }

  Future<void> _resetSavedAccount() async {
    if (_wallet == null) return;

    setState(() {
      _isUnlocking = true;
      _unlockError = null;
    });

    try {
      await _logoutRunner();
      if (!mounted) return;
      setState(() {
        _wallet = null;
        _lockStatus = null;
        _isLocked = false;
        _backgroundedAt = null;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _unlockError = AppLocalizations.of(
          context,
        )!.failedResetAccount(error.toString());
      });
    }

    if (!mounted) return;
    setState(() => _isUnlocking = false);
  }

  Future<void> _promptRecoveryPhraseUnlock() async {
    if (_wallet == null || _isUnlocking) return;

    final phrase = await showDialog<String>(
      context: context,
      builder: (ctx) {
        final controller = TextEditingController();
        return AlertDialog(
          backgroundColor: SpotColors.surface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(SpotRadius.md),
          ),
          title: Text(
            AppLocalizations.of(context)!.unlockWithPhraseDialogTitle,
            style: SpotType.subheading,
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                AppLocalizations.of(context)!.unlockPhraseDescription,
                style: SpotType.bodySecondary,
              ),
              const SizedBox(height: SpotSpacing.md),
              TextField(
                key: const Key('recovery_phrase_unlock_field'),
                controller: controller,
                autofocus: true,
                minLines: 2,
                maxLines: 4,
                autocorrect: false,
                enableSuggestions: false,
                textCapitalization: TextCapitalization.none,
                keyboardType: TextInputType.visiblePassword,
                decoration: const InputDecoration(
                  hintText: 'twelve recovery words',
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: Text(
                AppLocalizations.of(context)!.cancelAction,
                style: SpotType.bodySecondary,
              ),
            ),
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(controller.text),
              child: Text(AppLocalizations.of(context)!.unlockButton),
            ),
          ],
        );
      },
    );

    if (phrase == null) return;
    await _unlockWithRecoveryPhrase(phrase);
  }

  Future<void> _unlockWithRecoveryPhrase(String phrase) async {
    final wallet = _wallet;
    if (wallet == null || _isUnlocking) return;

    setState(() {
      _isUnlocking = true;
      _unlockError = null;
    });

    final validationError = validateRecoveryPhraseForWallet(wallet, phrase);
    if (!mounted) return;

    setState(() {
      _isUnlocking = false;
      if (validationError == null) {
        _isLocked = false;
        _backgroundedAt = null;
      } else {
        _unlockError = validationError;
      }
    });
  }

  Future<void> _acceptCurrentTerms() async {
    await _acceptTerms(currentUgcTermsVersion);
    if (!mounted) return;
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final wallet = _wallet;
    if (wallet == null) {
      return widget.onboardingBuilder?.call() ??
          const AltchaGateScreen(next: OnboardingScreen());
    }

    final requiresTerms = !_hasAcceptedTerms(currentUgcTermsVersion);

    if (!_safeModeEnabled) {
      if (requiresTerms) {
        return Scaffold(
          backgroundColor: SpotColors.bg,
          body: SafeArea(child: UgcTermsGate(onAccept: _acceptCurrentTerms)),
        );
      }
      return widget.unlockedBuilder?.call(wallet) ??
          SplashScreen(wallet: wallet);
    }

    if (_isCheckingLock || _lockStatus == null) {
      return Scaffold(
        body: AppLoadingView(
          title: AppLocalizations.of(context)!.securingAccountTitle,
          subtitle: AppLocalizations.of(context)!.checkingOwnerSubtitle,
        ),
      );
    }

    final lockStatus = _lockStatus!;
    if (_shouldShowUnlockedContent()) {
      if (requiresTerms) {
        return Scaffold(
          backgroundColor: SpotColors.bg,
          body: SafeArea(child: UgcTermsGate(onAccept: _acceptCurrentTerms)),
        );
      }
      return widget.unlockedBuilder?.call(wallet) ??
          SplashScreen(wallet: wallet);
    }

    return _LockedAccountScreen(
      wallet: wallet,
      status: lockStatus,
      isUnlocking: _isUnlocking,
      errorText: _unlockError,
      onUnlock: lockStatus.canAuthenticate
          ? () => _unlock(showErrorOnFailure: true)
          : null,
      onUnlockWithRecoveryPhrase: _promptRecoveryPhraseUnlock,
      onResetAccount: _resetSavedAccount,
    );
  }

  bool _shouldShowUnlockedContent() {
    if (_wallet == null || _isLocked || _isCheckingLock || _isUnlocking) {
      return false;
    }
    if (_unlockError != null) {
      return false;
    }
    return true;
  }
}

class _LockedAccountScreen extends StatelessWidget {
  const _LockedAccountScreen({
    required this.wallet,
    required this.status,
    required this.isUnlocking,
    required this.errorText,
    required this.onUnlock,
    required this.onUnlockWithRecoveryPhrase,
    required this.onResetAccount,
  });

  final WalletModel wallet;
  final AppLockStatus status;
  final bool isUnlocking;
  final String? errorText;
  final Future<void> Function()? onUnlock;
  final Future<void> Function() onUnlockWithRecoveryPhrase;
  final Future<void> Function() onResetAccount;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Scaffold(
      backgroundColor: SpotColors.bg,
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            return SingleChildScrollView(
              padding: const EdgeInsets.all(SpotSpacing.xxl),
              child: ConstrainedBox(
                constraints: BoxConstraints(minHeight: constraints.maxHeight),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 420),
                    child: DecoratedBox(
                      decoration: SpotDecoration.cardBordered(
                        radius: SpotRadius.lg,
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(SpotSpacing.xxl),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Container(
                              width: 56,
                              height: 56,
                              decoration: BoxDecoration(
                                color: SpotColors.accentSubtle,
                                borderRadius: BorderRadius.circular(
                                  SpotRadius.full,
                                ),
                                border: Border.all(
                                  color: SpotColors.accent.withAlpha(70),
                                  width: 0.5,
                                ),
                              ),
                              child: const Icon(
                                Icons.lock_outline_rounded,
                                color: SpotColors.accent,
                              ),
                            ),
                            const SizedBox(height: SpotSpacing.xl),
                            Text(
                              l10n.savedAccountLockedTitle,
                              style: SpotType.heading,
                            ),
                            const SizedBox(height: SpotSpacing.sm),
                            Text(status.message, style: SpotType.bodySecondary),
                            const SizedBox(height: SpotSpacing.xl),
                            _MetaRow(
                              label: l10n.accountLabel,
                              value: wallet.npubShort,
                            ),
                            _MetaRow(
                              label: l10n.createdLabel,
                              value: wallet.createdAt
                                  .toLocal()
                                  .toString()
                                  .substring(0, 16),
                            ),
                            const SizedBox(height: SpotSpacing.xl),
                            Container(
                              padding: const EdgeInsets.all(SpotSpacing.lg),
                              decoration: SpotDecoration.danger(),
                              child: Text(
                                l10n.accountLockedDescription,
                                style: SpotType.bodySecondary,
                              ),
                            ),
                            if (errorText != null) ...[
                              const SizedBox(height: SpotSpacing.lg),
                              Text(
                                errorText!,
                                style: SpotType.caption.copyWith(
                                  color: SpotColors.danger,
                                ),
                              ),
                            ],
                            const SizedBox(height: SpotSpacing.xl),
                            if (status.canAuthenticate)
                              SizedBox(
                                width: double.infinity,
                                child: FilledButton(
                                  onPressed: isUnlocking ? null : onUnlock,
                                  child: isUnlocking
                                      ? const SizedBox(
                                          width: 16,
                                          height: 16,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 1.5,
                                            color: SpotColors.onAccent,
                                          ),
                                        )
                                      : Text(l10n.unlockThisAccountButton),
                                ),
                              ),
                            if (status.canAuthenticate)
                              const SizedBox(height: SpotSpacing.md),
                            SizedBox(
                              width: double.infinity,
                              child: OutlinedButton(
                                onPressed: isUnlocking
                                    ? null
                                    : onUnlockWithRecoveryPhrase,
                                child: Text(l10n.unlockWithPhraseButton),
                              ),
                            ),
                            const SizedBox(height: SpotSpacing.md),
                            SizedBox(
                              width: double.infinity,
                              child: OutlinedButton(
                                onPressed: isUnlocking ? null : onResetAccount,
                                child: Text(l10n.notMyAccountButton),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

class _MetaRow extends StatelessWidget {
  const _MetaRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: SpotSpacing.xs),
      child: Row(
        children: [
          SizedBox(width: 64, child: Text(label, style: SpotType.label)),
          Expanded(child: Text(value, style: SpotType.bodySecondary)),
        ],
      ),
    );
  }
}
