import 'dart:async';

import 'package:flutter/material.dart';

import 'package:mobile/models/wallet_model.dart';
import 'package:mobile/screens/altcha_gate_screen.dart';
import 'package:mobile/screens/onboarding_screen.dart';
import 'package:mobile/screens/splash_screen.dart';
import 'package:mobile/services/app_lock_service.dart';
import 'package:mobile/services/session_logout_service.dart';
import 'package:mobile/theme/spot_theme.dart';
import 'package:mobile/widgets/app_loading_view.dart';

typedef SessionUnlockedBuilder = Widget Function(WalletModel wallet);
typedef SessionOnboardingBuilder = Widget Function();
typedef SessionLogoutRunner = Future<void> Function();

class SessionGateScreen extends StatefulWidget {
  const SessionGateScreen({
    super.key,
    this.initialWallet,
    this.appLockService,
    this.logoutRunner,
    this.unlockedBuilder,
    this.onboardingBuilder,
    this.relockAfter = const Duration(minutes: 2),
  });

  final WalletModel? initialWallet;
  final AppLockService? appLockService;
  final SessionLogoutRunner? logoutRunner;
  final SessionUnlockedBuilder? unlockedBuilder;
  final SessionOnboardingBuilder? onboardingBuilder;
  final Duration relockAfter;

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

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _wallet = widget.initialWallet;
    _isLocked = _wallet != null;
    if (_wallet != null) {
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
    if (_wallet == null) return;

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
        _unlockError =
            'Unlock was cancelled or failed. Spot will stay locked until this device owner confirms access.';
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
        _unlockError = 'Failed to reset the saved account: $error';
      });
    }

    if (!mounted) return;
    setState(() => _isUnlocking = false);
  }

  @override
  Widget build(BuildContext context) {
    final wallet = _wallet;
    if (wallet == null) {
      return widget.onboardingBuilder?.call() ??
          const AltchaGateScreen(next: OnboardingScreen());
    }

    if (_isCheckingLock || _lockStatus == null) {
      return const Scaffold(
        body: AppLoadingView(
          title: 'Securing account',
          subtitle: 'Checking how this device can verify the saved owner…',
        ),
      );
    }

    final lockStatus = _lockStatus!;
    if (_shouldShowUnlockedContent(lockStatus)) {
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
      onResetAccount: _resetSavedAccount,
    );
  }

  bool _shouldShowUnlockedContent(AppLockStatus status) {
    if (_wallet == null || _isLocked || _isCheckingLock || _isUnlocking) {
      return false;
    }
    if (_unlockError != null) {
      return false;
    }
    return status.canAuthenticate;
  }
}

class _LockedAccountScreen extends StatelessWidget {
  const _LockedAccountScreen({
    required this.wallet,
    required this.status,
    required this.isUnlocking,
    required this.errorText,
    required this.onUnlock,
    required this.onResetAccount,
  });

  final WalletModel wallet;
  final AppLockStatus status;
  final bool isUnlocking;
  final String? errorText;
  final Future<void> Function()? onUnlock;
  final Future<void> Function() onResetAccount;

  @override
  Widget build(BuildContext context) {
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
                            const Text(
                              'Saved account locked',
                              style: SpotType.heading,
                            ),
                            const SizedBox(height: SpotSpacing.sm),
                            Text(status.message, style: SpotType.bodySecondary),
                            const SizedBox(height: SpotSpacing.xl),
                            _MetaRow(label: 'Account', value: wallet.npubShort),
                            _MetaRow(
                              label: 'Created',
                              value: wallet.createdAt
                                  .toLocal()
                                  .toString()
                                  .substring(0, 16),
                            ),
                            const SizedBox(height: SpotSpacing.xl),
                            Container(
                              padding: const EdgeInsets.all(SpotSpacing.lg),
                              decoration: SpotDecoration.danger(),
                              child: const Text(
                                'Public threads stay public, but private account access on this phone stays locked until the current owner unlocks or resets it.',
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
                                      : const Text('Unlock this account'),
                                ),
                              ),
                            if (status.canAuthenticate)
                              const SizedBox(height: SpotSpacing.md),
                            SizedBox(
                              width: double.infinity,
                              child: OutlinedButton(
                                onPressed: isUnlocking ? null : onResetAccount,
                                child: const Text('This is not my account'),
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
