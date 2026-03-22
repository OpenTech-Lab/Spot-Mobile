import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:mobile/models/wallet_model.dart';
import 'package:mobile/screens/home_screen.dart';
import 'package:mobile/screens/onboarding_screen.dart';
import 'package:mobile/services/storage_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Lock orientation to portrait
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);

  // Set immersive dark system UI
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
      systemNavigationBarColor: Color(0xFF0D0D0D),
      systemNavigationBarIconBrightness: Brightness.light,
    ),
  );

  // Check for an existing wallet — decide whether to show onboarding or home
  final wallet = await StorageService.instance.loadWallet();

  runApp(SpotApp(initialWallet: wallet));
}

/// Root application widget for "Spot" (Citizen Swarm).
class SpotApp extends StatelessWidget {
  const SpotApp({super.key, this.initialWallet});

  final WalletModel? initialWallet;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Spot',
      debugShowCheckedModeBanner: false,
      theme: _buildTheme(),
      home: initialWallet != null
          ? HomeScreen(wallet: initialWallet!)
          : const OnboardingScreen(),
    );
  }

  ThemeData _buildTheme() {
    const accent = Color(0xFFFF4444);
    const background = Color(0xFF0D0D0D);
    const surface = Color(0xFF1A1A1A);

    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      scaffoldBackgroundColor: background,
      colorScheme: const ColorScheme.dark(
        primary: accent,
        secondary: accent,
        surface: surface,
        onPrimary: Colors.white,
        onSecondary: Colors.white,
        onSurface: Colors.white,
        error: Color(0xFFCF6679),
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: background,
        foregroundColor: Colors.white,
        elevation: 0,
        centerTitle: false,
        titleTextStyle: TextStyle(
          color: Colors.white,
          fontSize: 18,
          fontWeight: FontWeight.bold,
        ),
      ),
      bottomNavigationBarTheme: const BottomNavigationBarThemeData(
        backgroundColor: Color(0xFF111111),
        selectedItemColor: accent,
        unselectedItemColor: Colors.white38,
        type: BottomNavigationBarType.fixed,
        elevation: 0,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: surface,
        hintStyle: const TextStyle(color: Colors.white38),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide.none,
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: accent,
          foregroundColor: Colors.white,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      ),
      snackBarTheme: const SnackBarThemeData(
        backgroundColor: surface,
        contentTextStyle: TextStyle(color: Colors.white),
      ),
      textTheme: const TextTheme(
        bodyLarge: TextStyle(color: Colors.white),
        bodyMedium: TextStyle(color: Colors.white70),
        bodySmall: TextStyle(color: Colors.white54),
        titleLarge:
            TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        titleMedium: TextStyle(color: Colors.white),
        labelLarge: TextStyle(color: Colors.white),
      ),
    );
  }
}
