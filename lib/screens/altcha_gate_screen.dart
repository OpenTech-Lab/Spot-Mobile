import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import 'package:mobile/core/altcha.dart';
import 'package:mobile/theme/spot_theme.dart';

/// Full-screen gate shown on every cold start.
///
/// Automatically generates and solves an ALTCHA proof-of-work challenge
/// (~50 k SHA-256 hashes) in a background isolate.  Real users see a
/// brief "Verifying…" spinner (typically < 2 s); scripted bots pay the
/// same CPU cost on every launch, making mass automation uneconomical.
///
/// On success the screen pushes [next] via [Navigator.pushReplacement].
class AltchaGateScreen extends StatefulWidget {
  const AltchaGateScreen({super.key, required this.next});

  /// The widget to reveal after verification succeeds.
  final Widget next;

  @override
  State<AltchaGateScreen> createState() => _AltchaGateScreenState();
}

enum _VerifyState { verifying, verified, failed }

class _AltchaGateScreenState extends State<AltchaGateScreen> {
  _VerifyState _state = _VerifyState.verifying;

  @override
  void initState() {
    super.initState();
    _run();
  }

  Future<void> _run() async {
    setState(() => _state = _VerifyState.verifying);

    try {
      final challenge = AltchaService.generate();
      final solution = await AltchaService.solve(challenge);

      if (solution == null || !AltchaService.verify(challenge, solution)) {
        if (mounted) setState(() => _state = _VerifyState.failed);
        return;
      }
    } catch (_) {
      if (mounted) setState(() => _state = _VerifyState.failed);
      return;
    }

    if (!mounted) return;
    setState(() => _state = _VerifyState.verified);

    // Hold the verified state briefly so the user sees it before proceeding.
    await Future.delayed(const Duration(milliseconds: 600));

    if (mounted) {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute<void>(builder: (_) => widget.next),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: SpotColors.bg,
      body: SafeArea(
        child: Center(
          child: Padding(
            padding:
                const EdgeInsets.symmetric(horizontal: SpotSpacing.xxxl),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // App logo
                Image.asset(
                  'assets/logo_transparent.png',
                  height: 44,
                  fit: BoxFit.contain,
                ),
                const SizedBox(height: SpotSpacing.xxxl),

                // Animated badge
                _AltchaBadge(state: _state),
                const SizedBox(height: SpotSpacing.lg),

                // Status label
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 200),
                  child: Text(
                    key: ValueKey(_state),
                    switch (_state) {
                      _VerifyState.verifying => 'Verifying…',
                      _VerifyState.verified  => 'Verified',
                      _VerifyState.failed    => 'Verification failed',
                    },
                    style: switch (_state) {
                      _VerifyState.verified =>
                        SpotType.label.copyWith(color: SpotColors.success),
                      _VerifyState.failed =>
                        SpotType.label.copyWith(color: SpotColors.danger),
                      _VerifyState.verifying => SpotType.caption,
                    },
                  ),
                ),

                // Retry button — only shown on failure
                if (_state == _VerifyState.failed) ...[
                  const SizedBox(height: SpotSpacing.xl),
                  GestureDetector(
                    onTap: _run,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: SpotSpacing.xl,
                        vertical: SpotSpacing.sm,
                      ),
                      decoration: BoxDecoration(
                        border: Border.all(
                            color: SpotColors.border, width: 0.5),
                        borderRadius:
                            BorderRadius.circular(SpotRadius.sm),
                      ),
                      child: Text('Retry', style: SpotType.bodySecondary),
                    ),
                  ),
                ],

                const SizedBox(height: SpotSpacing.xxxl),

                // ALTCHA attribution
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      CupertinoIcons.shield_lefthalf_fill,
                      color: SpotColors.textTertiary,
                      size: 11,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      'Protected by ALTCHA',
                      style: SpotType.caption,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ── Badge ─────────────────────────────────────────────────────────────────────

class _AltchaBadge extends StatelessWidget {
  const _AltchaBadge({required this.state});

  final _VerifyState state;

  @override
  Widget build(BuildContext context) {
    final Color borderColor = switch (state) {
      _VerifyState.verified  => SpotColors.success.withAlpha(100),
      _VerifyState.failed    => SpotColors.danger.withAlpha(100),
      _VerifyState.verifying => SpotColors.border,
    };
    final Color bgColor = switch (state) {
      _VerifyState.verified  => SpotColors.success.withAlpha(20),
      _VerifyState.failed    => SpotColors.danger.withAlpha(20),
      _VerifyState.verifying => SpotColors.surface,
    };

    return Container(
      width: 64,
      height: 64,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: bgColor,
        border: Border.all(color: borderColor, width: 0.5),
      ),
      child: Center(
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 300),
          child: switch (state) {
            _VerifyState.verifying => const SizedBox(
                key: ValueKey('spinner'),
                width: 22,
                height: 22,
                child: CircularProgressIndicator(
                  color: SpotColors.accent,
                  strokeWidth: 1.5,
                ),
              ),
            _VerifyState.verified => const Icon(
                key: ValueKey('ok'),
                CupertinoIcons.checkmark_alt,
                color: SpotColors.success,
                size: 26,
              ),
            _VerifyState.failed => const Icon(
                key: ValueKey('fail'),
                CupertinoIcons.xmark,
                color: SpotColors.danger,
                size: 26,
              ),
          },
        ),
      ),
    );
  }
}
