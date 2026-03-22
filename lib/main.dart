import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:mobile/models/wallet_model.dart';
import 'package:mobile/screens/altcha_gate_screen.dart';
import 'package:mobile/screens/onboarding_screen.dart';
import 'package:mobile/screens/splash_screen.dart';
import 'package:mobile/services/cache_manager.dart';
import 'package:mobile/services/geo_lookup.dart';
import 'package:mobile/services/storage_service.dart';
import 'package:mobile/theme/spot_theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialise cache manager early so eviction & blocklist are ready before
  // any media or feed content loads (spec v1.4 §6 & §12.B).
  await CacheManager.instance.init();
  await GeoLookup.instance.init(); // loads Natural Earth cities into memory

  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);

  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor:                    Colors.transparent,
      statusBarIconBrightness:           Brightness.light,
      systemNavigationBarColor:          SpotColors.bg,
      systemNavigationBarIconBrightness: Brightness.light,
    ),
  );

  final wallet = await StorageService.instance.loadWallet();
  runApp(SpotApp(initialWallet: wallet));
}

class SpotApp extends StatelessWidget {
  const SpotApp({super.key, this.initialWallet});

  final WalletModel? initialWallet;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Spot',
      debugShowCheckedModeBanner: false,
      theme: SpotTheme.build(),
      // Returning users: silent splash + ALTCHA, then HomeScreen.
      // New users: explicit ALTCHA gate, then OnboardingScreen.
      home: initialWallet != null
          ? SplashScreen(wallet: initialWallet!)
          : AltchaGateScreen(next: const OnboardingScreen()),
    );
  }
}
