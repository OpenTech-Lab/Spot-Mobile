import 'package:flutter/material.dart';

import 'package:mobile/core/altcha.dart';
import 'package:mobile/models/wallet_model.dart';
import 'package:mobile/screens/home_screen.dart';
import 'package:mobile/theme/spot_theme.dart';

/// Minimal splash shown every time a logged-in user re-opens the app.
///
/// Displays only the logo while an ALTCHA proof-of-work challenge is solved
/// silently in a background isolate.  On success the screen is replaced by
/// [HomeScreen]; on the rare failure it automatically retries once.
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key, required this.wallet});

  final WalletModel wallet;

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _fade;
  late final Animation<double> _opacity;

  @override
  void initState() {
    super.initState();
    _fade = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    )..forward();
    _opacity = CurvedAnimation(parent: _fade, curve: Curves.easeIn);
    _verify();
  }

  @override
  void dispose() {
    _fade.dispose();
    super.dispose();
  }

  Future<void> _verify({bool isRetry = false}) async {
    try {
      final challenge = AltchaService.generate();
      final solution = await AltchaService.solve(challenge);
      if (solution == null || !AltchaService.verify(challenge, solution)) {
        // Virtually impossible for a self-generated challenge, but retry once.
        if (!isRetry && mounted) _verify(isRetry: true);
        return;
      }
    } catch (_) {
      if (!isRetry && mounted) _verify(isRetry: true);
      return;
    }

    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute<void>(
        builder: (_) => HomeScreen(wallet: widget.wallet),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: SpotColors.bg,
      body: Center(
        child: FadeTransition(
          opacity: _opacity,
          child: Image.asset(
            'assets/logo_transparent.png',
            height: 36,
            fit: BoxFit.contain,
          ),
        ),
      ),
    );
  }
}
