import 'package:flutter/material.dart';

// ═══════════════════════════════════════════════════════════════════════════════
// Spot Design System
// ── Tailwind-inspired design tokens for Flutter.
//
// Usage:
//   import 'package:mobile/theme/spot_theme.dart';
//   SpotColors.bg, SpotSpacing.lg, SpotRadius.md, SpotType.heading ...
// ═══════════════════════════════════════════════════════════════════════════════

// ── Colors ────────────────────────────────────────────────────────────────────

abstract final class SpotColors {
  SpotColors._();

  // Backgrounds (darkest → lightest)
  static const Color bg           = Color(0xFF111111); // canvas / page
  static const Color surface      = Color(0xFF1B1B1B); // cards, inputs
  static const Color surfaceHigh  = Color(0xFF222222); // elevated chips, tags
  static const Color overlay      = Color(0xFF2A2A2A); // overlays, pressed states

  // Dividers / borders
  static const Color border       = Color(0xFF222222);
  static const Color borderSubtle = Color(0xFF1A1A1A);

  // Text
  static const Color textPrimary   = Color(0xFFE2DDD6); // warm off-white
  static const Color textSecondary = Color(0xFF888480); // warm medium gray
  static const Color textTertiary  = Color(0xFF4E4C49); // warm dim gray

  // Accent — warm sand / stone
  static const Color accent        = Color(0xFFC8B89A);
  static const Color accentSubtle  = Color(0xFF2A2520); // tinted surface
  static const Color onAccent      = Color(0xFF111111); // text on accent bg

  // Danger — muted terracotta  (for Danger Mode, errors)
  static const Color danger        = Color(0xFFBC4E3A);
  static const Color dangerSubtle  = Color(0xFF251410); // tinted surface
  static const Color onDanger      = Color(0xFFFFFFFF);

  // Success — muted sage green
  static const Color success       = Color(0xFF6B8F6F);
  static const Color successSubtle = Color(0xFF162018);
  static const Color onSuccess     = Color(0xFFFFFFFF);

  // Warning — warm amber
  static const Color warning       = Color(0xFFC09040);
  static const Color warningSubtle = Color(0xFF251E0A);
}

// ── Spacing ───────────────────────────────────────────────────────────────────
// Maps to: 1 = 4px, 2 = 8px, 3 = 12px, 4 = 16px, 6 = 24px, 8 = 32px, etc.

abstract final class SpotSpacing {
  SpotSpacing._();

  static const double px1  =  1.0;
  static const double xs   =  4.0;  // 1x
  static const double sm   =  8.0;  // 2x
  static const double md   = 12.0;  // 3x
  static const double lg   = 16.0;  // 4x
  static const double xl   = 24.0;  // 6x
  static const double xxl  = 32.0;  // 8x
  static const double xxxl = 40.0;  // 10x
  static const double huge = 56.0;  // 14x
}

// ── Border radius ─────────────────────────────────────────────────────────────

abstract final class SpotRadius {
  SpotRadius._();

  static const double none = 0;
  static const double xs   = 3.0;
  static const double sm   = 5.0;
  static const double md   = 7.0;
  static const double lg   = 10.0;
  static const double xl   = 14.0;
  static const double full = 999.0;
}

// ── Typography ────────────────────────────────────────────────────────────────

abstract final class SpotType {
  SpotType._();

  // App wordmark (e.g. top of home)
  static const TextStyle wordmark = TextStyle(
    color: SpotColors.textPrimary,
    fontSize: 20,
    fontWeight: FontWeight.w200,
    letterSpacing: 5,
  );

  // Large section headings
  static const TextStyle heading = TextStyle(
    color: SpotColors.textPrimary,
    fontSize: 24,
    fontWeight: FontWeight.w300,
    letterSpacing: 0.3,
    height: 1.3,
  );

  // Subheading / card titles
  static const TextStyle subheading = TextStyle(
    color: SpotColors.textPrimary,
    fontSize: 16,
    fontWeight: FontWeight.w400,
    letterSpacing: 0.1,
  );

  // Standard body text (primary)
  static const TextStyle body = TextStyle(
    color: SpotColors.textPrimary,
    fontSize: 14,
    fontWeight: FontWeight.w400,
    height: 1.5,
  );

  // Secondary body / descriptions
  static const TextStyle bodySecondary = TextStyle(
    color: SpotColors.textSecondary,
    fontSize: 13,
    fontWeight: FontWeight.w400,
    height: 1.6,
  );

  // Small captions / meta
  static const TextStyle caption = TextStyle(
    color: SpotColors.textTertiary,
    fontSize: 11,
    letterSpacing: 0.3,
  );

  // Monospace — for hashes, pubkeys, mnemonics
  static const TextStyle mono = TextStyle(
    color: SpotColors.textSecondary,
    fontSize: 10,
    letterSpacing: 0.5,
    fontFamily: 'monospace',
  );

  // Hashtag / event label
  static const TextStyle tag = TextStyle(
    color: SpotColors.textPrimary,
    fontSize: 14,
    fontWeight: FontWeight.w400,
    letterSpacing: 0.2,
  );

  // Uppercase label (e.g. section titles)
  static const TextStyle label = TextStyle(
    color: SpotColors.textTertiary,
    fontSize: 10,
    fontWeight: FontWeight.w500,
    letterSpacing: 1.5,
  );
}

// ── Decoration helpers ────────────────────────────────────────────────────────

abstract final class SpotDecoration {
  SpotDecoration._();

  /// Standard card / surface box decoration.
  static BoxDecoration card({double radius = SpotRadius.sm}) => BoxDecoration(
        color: SpotColors.surface,
        borderRadius: BorderRadius.circular(radius),
      );

  /// Card with a hairline border.
  static BoxDecoration cardBordered({double radius = SpotRadius.sm}) => BoxDecoration(
        color: SpotColors.surface,
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(color: SpotColors.border, width: 0.5),
      );

  /// Input field decoration.
  static BoxDecoration input({double radius = SpotRadius.sm}) => BoxDecoration(
        color: SpotColors.surface,
        borderRadius: BorderRadius.circular(radius),
      );

  /// Danger-tinted surface.
  static BoxDecoration danger({double radius = SpotRadius.sm}) => BoxDecoration(
        color: SpotColors.dangerSubtle,
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(color: SpotColors.danger.withAlpha(80), width: 0.5),
      );
}

// ── ThemeData ─────────────────────────────────────────────────────────────────

abstract final class SpotTheme {
  SpotTheme._();

  static ThemeData build() => ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        scaffoldBackgroundColor: SpotColors.bg,
        pageTransitionsTheme: const PageTransitionsTheme(
          builders: {
            TargetPlatform.android: CupertinoPageTransitionsBuilder(),
            TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
          },
        ),
        colorScheme: const ColorScheme.dark(
          primary:     SpotColors.accent,
          secondary:   SpotColors.accent,
          surface:     SpotColors.surface,
          onPrimary:   SpotColors.onAccent,
          onSecondary: SpotColors.onAccent,
          onSurface:   SpotColors.textPrimary,
          error:       SpotColors.danger,
          onError:     SpotColors.onDanger,
        ),
        appBarTheme: const AppBarTheme(
          backgroundColor:          SpotColors.bg,
          foregroundColor:          SpotColors.textPrimary,
          elevation:                0,
          scrolledUnderElevation:   0,
          centerTitle:              false,
          titleTextStyle: TextStyle(
            color: SpotColors.textPrimary,
            fontSize: 17,
            fontWeight: FontWeight.w400,
            letterSpacing: 0.2,
          ),
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled:    true,
          fillColor: SpotColors.surface,
          hintStyle: const TextStyle(color: SpotColors.textTertiary),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(SpotRadius.sm),
            borderSide: BorderSide.none,
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(SpotRadius.sm),
            borderSide: const BorderSide(color: SpotColors.accent, width: 0.5),
          ),
          contentPadding: const EdgeInsets.symmetric(
            horizontal: SpotSpacing.lg,
            vertical: SpotSpacing.md,
          ),
        ),
        filledButtonTheme: FilledButtonThemeData(
          style: FilledButton.styleFrom(
            backgroundColor:         SpotColors.accent,
            foregroundColor:         SpotColors.onAccent,
            disabledBackgroundColor: SpotColors.surfaceHigh,
            disabledForegroundColor: SpotColors.textTertiary,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(SpotRadius.sm),
            ),
            textStyle: const TextStyle(
              fontWeight: FontWeight.w500,
              letterSpacing: 0.3,
              fontSize: 14,
            ),
          ),
        ),
        outlinedButtonTheme: OutlinedButtonThemeData(
          style: OutlinedButton.styleFrom(
            foregroundColor: SpotColors.textSecondary,
            side: const BorderSide(color: SpotColors.border, width: 0.5),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(SpotRadius.sm),
            ),
            textStyle: const TextStyle(fontWeight: FontWeight.w400, fontSize: 14),
          ),
        ),
        textButtonTheme: TextButtonThemeData(
          style: TextButton.styleFrom(
            foregroundColor: SpotColors.accent,
            textStyle: const TextStyle(fontWeight: FontWeight.w400, fontSize: 13),
          ),
        ),
        dividerTheme: const DividerThemeData(
          color:     SpotColors.border,
          thickness: 0.5,
          space:     0,
        ),
        chipTheme: ChipThemeData(
          backgroundColor: SpotColors.surfaceHigh,
          labelStyle: SpotType.caption,
          side: BorderSide.none,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(SpotRadius.xs),
          ),
          padding: const EdgeInsets.symmetric(horizontal: SpotSpacing.sm),
        ),
        snackBarTheme: const SnackBarThemeData(
          backgroundColor:  SpotColors.surfaceHigh,
          contentTextStyle: TextStyle(color: SpotColors.textPrimary, fontSize: 13),
        ),
        textTheme: const TextTheme(
          bodyLarge:   TextStyle(color: SpotColors.textPrimary),
          bodyMedium:  TextStyle(color: SpotColors.textSecondary),
          bodySmall:   TextStyle(color: SpotColors.textTertiary),
          titleLarge:  SpotType.heading,
          titleMedium: SpotType.subheading,
          labelLarge:  TextStyle(color: SpotColors.textPrimary),
        ),
      );
}
