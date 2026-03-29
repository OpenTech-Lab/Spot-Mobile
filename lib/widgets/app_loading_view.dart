import 'package:flutter/material.dart';

import 'package:mobile/theme/spot_theme.dart';

class AppLoadingView extends StatelessWidget {
  const AppLoadingView({super.key, required this.title, this.subtitle});

  final String title;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: SpotColors.bg,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: SpotSpacing.xxxl),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Image.asset(
                'assets/logo_transparent.png',
                height: 40,
                fit: BoxFit.contain,
                errorBuilder: (context, error, stackTrace) => const Icon(
                  Icons.radio_button_checked,
                  color: SpotColors.textSecondary,
                  size: 24,
                ),
              ),
              const SizedBox(height: SpotSpacing.xl),
              ClipRRect(
                borderRadius: BorderRadius.circular(SpotRadius.full),
                child: const SizedBox(
                  width: 160,
                  child: LinearProgressIndicator(
                    minHeight: 4,
                    color: SpotColors.accent,
                    backgroundColor: SpotColors.surface,
                  ),
                ),
              ),
              const SizedBox(height: SpotSpacing.lg),
              Text(title, style: SpotType.label),
              if (subtitle != null) ...[
                const SizedBox(height: SpotSpacing.sm),
                Text(
                  subtitle!,
                  textAlign: TextAlign.center,
                  style: SpotType.caption,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
