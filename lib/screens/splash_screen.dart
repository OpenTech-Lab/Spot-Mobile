import 'dart:async';

import 'package:flutter/material.dart';

import 'package:mobile/core/altcha.dart';
import 'package:mobile/models/wallet_model.dart';
import 'package:mobile/screens/home_screen.dart';
import 'package:mobile/services/app_refresh_service.dart';
import 'package:mobile/widgets/app_loading_view.dart';

typedef SplashHomeBuilder = Widget Function(WalletModel wallet);
typedef SplashVerificationRunner = Future<void> Function();

/// Session entry screen for signed-in users.
///
/// Shows a loading page on cold launch and again whenever the app resumes,
/// warming recent metadata into local storage before handing control back to
/// the main shell.
class SplashScreen extends StatefulWidget {
  const SplashScreen({
    super.key,
    required this.wallet,
    this.refreshService,
    this.homeBuilder,
    this.verificationRunner,
  });

  final WalletModel wallet;
  final AppRefreshService? refreshService;
  final SplashHomeBuilder? homeBuilder;
  final SplashVerificationRunner? verificationRunner;

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with WidgetsBindingObserver {
  final GlobalKey<HomeScreenState> _homeKey = GlobalKey<HomeScreenState>();
  bool _isReady = false;
  bool _isRefreshing = false;

  AppRefreshService get _refreshService =>
      widget.refreshService ?? AppRefreshService.instance;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(_runInitialLoad());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed || !_isReady) return;
    unawaited(_refreshOnResume());
  }

  Future<void> _runInitialLoad() async {
    if (_isRefreshing) return;
    setState(() => _isRefreshing = true);

    await _runRefreshSequence(includeVerification: true);

    if (!mounted) return;
    setState(() {
      _isReady = true;
      _isRefreshing = false;
    });
  }

  Future<void> _refreshOnResume() async {
    if (_isRefreshing) return;
    setState(() => _isRefreshing = true);

    await _runRefreshSequence(includeVerification: false);
    await _homeKey.currentState?.triggerSessionRefresh();

    if (!mounted) return;
    setState(() => _isRefreshing = false);
  }

  Future<void> _runRefreshSequence({required bool includeVerification}) async {
    Object? lastError;
    for (var attempt = 0; attempt < 2; attempt++) {
      try {
        if (includeVerification) {
          await _runVerification();
        }
        await _refreshService.refreshSessionData(widget.wallet);
        return;
      } catch (error) {
        lastError = error;
      }
    }

    if (lastError != null) {
      debugPrint('[SplashScreen] Session refresh failed: $lastError');
    }
  }

  Future<void> _runVerification() async {
    if (widget.verificationRunner != null) {
      await widget.verificationRunner!();
      return;
    }

    final challenge = AltchaService.generate();
    final solution = await AltchaService.solve(challenge);
    if (solution == null || !AltchaService.verify(challenge, solution)) {
      throw StateError('ALTCHA verification failed');
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_isReady) {
      return const Scaffold(
        body: AppLoadingView(
          title: 'Loading Spot',
          subtitle: 'Fetching latest data and saving it locally…',
        ),
      );
    }

    final home =
        widget.homeBuilder?.call(widget.wallet) ??
        HomeScreen(key: _homeKey, wallet: widget.wallet);

    return Stack(
      children: [
        home,
        if (_isRefreshing)
          const Positioned.fill(
            child: Material(
              color: Colors.transparent,
              child: AppLoadingView(
                title: 'Refreshing data…',
                subtitle: 'Checking for new posts and saving updates locally…',
              ),
            ),
          ),
      ],
    );
  }
}
