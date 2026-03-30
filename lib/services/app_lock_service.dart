import 'package:flutter/foundation.dart';
import 'package:local_auth/local_auth.dart';

class AppLockStatus {
  const AppLockStatus({required this.canAuthenticate, required this.message});

  final bool canAuthenticate;
  final String message;
}

class AppLockService {
  AppLockService({LocalAuthentication? localAuth})
    : _localAuth = localAuth ?? LocalAuthentication();

  static final AppLockService instance = AppLockService();

  final LocalAuthentication _localAuth;

  Future<AppLockStatus> getStatus() async {
    try {
      final canCheckBiometrics = await _localAuth.canCheckBiometrics;
      final isDeviceSupported = await _localAuth.isDeviceSupported();
      final biometrics = await _localAuth.getAvailableBiometrics();
      final canAuthenticate =
          canCheckBiometrics || isDeviceSupported || biometrics.isNotEmpty;

      if (canAuthenticate) {
        return const AppLockStatus(
          canAuthenticate: true,
          message:
              'Unlock this saved account with Face ID, biometrics, or your device passcode.',
        );
      }
    } catch (error) {
      debugPrint('[AppLockService] Failed to inspect local auth: $error');
    }

    return const AppLockStatus(
      canAuthenticate: false,
      message:
          'This device cannot confirm local ownership. Reset the saved account before using Spot on this phone.',
    );
  }

  Future<bool> authenticate() async {
    try {
      return await _localAuth.authenticate(
        localizedReason:
            'Unlock Spot to access the saved account on this device.',
        options: const AuthenticationOptions(
          biometricOnly: false,
          stickyAuth: true,
          useErrorDialogs: true,
        ),
      );
    } catch (error) {
      debugPrint('[AppLockService] Unlock threw unexpectedly: $error');
      return false;
    }
  }
}
