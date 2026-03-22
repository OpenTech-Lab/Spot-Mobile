import 'dart:io';

import 'package:device_info_plus/device_info_plus.dart';

import 'package:mobile/core/encryption.dart';

/// Hardware attestation service.
///
/// Prototype implementation using [device_info_plus] to create a stable
/// device fingerprint.  The real implementation must integrate:
///   - Android: Play Integrity API (replaces SafetyNet)
///   - iOS: App Attest / DeviceCheck
///
/// Both platforms produce a signed proof from the manufacturer's hardware that:
///   1. The device is real and not emulated.
///   2. The app binary is unmodified.
///   3. The device has not been rooted or jailbroken.
///
/// TODO: Replace stub with Play Integrity (Android) and App Attest (iOS).
class AttestationService {
  AttestationService._();

  static final DeviceInfoPlugin _deviceInfo = DeviceInfoPlugin();

  // ── Device identity ───────────────────────────────────────────────────────

  /// Returns a stable hardware identifier for this device.
  ///
  /// Android: uses [AndroidDeviceInfo.id] (stable across reboots).
  /// iOS: uses [IosDeviceInfo.identifierForVendor] (stable until app reinstall).
  /// Other platforms: falls back to a SHA-256 of OS + model info.
  static Future<String> getDeviceId() async {
    try {
      if (Platform.isAndroid) {
        final info = await _deviceInfo.androidInfo;
        return info.id;
      } else if (Platform.isIOS) {
        final info = await _deviceInfo.iosInfo;
        return info.identifierForVendor ?? _fallbackId(info.name, info.model);
      }
    } catch (_) {
      // Fall through to generic fingerprint
    }
    return await _genericDeviceId();
  }

  // ── Attestation proof ─────────────────────────────────────────────────────

  /// Generates an attestation proof string.
  ///
  /// Prototype: SHA-256 of key device attributes (model, OS version, device ID).
  /// Production: call Play Integrity / App Attest API and return the signed JWT.
  static Future<String> generateAttestationProof() async {
    final deviceId = await getDeviceId();
    final fingerprint = await _buildFingerprint(deviceId);
    final proof = EncryptionUtils.sha256Hex(fingerprint);
    return 'proto_attest:$proof'; // prefix signals prototype mode to verifiers
  }

  /// Verifies an attestation proof.
  ///
  /// Prototype: re-computes the expected proof and compares.
  /// Production: validate the signed JWT from Play Integrity / App Attest.
  static Future<bool> verifyAttestation(String proof) async {
    if (!proof.startsWith('proto_attest:')) {
      // TODO: implement Play Integrity / App Attest JWT verification
      return false;
    }
    final expected = await generateAttestationProof();
    return proof == expected;
  }

  // ── Private helpers ───────────────────────────────────────────────────────

  static Future<String> _buildFingerprint(String deviceId) async {
    final parts = <String>[deviceId];
    try {
      if (Platform.isAndroid) {
        final info = await _deviceInfo.androidInfo;
        parts.addAll([info.model, info.brand, info.version.release]);
      } else if (Platform.isIOS) {
        final info = await _deviceInfo.iosInfo;
        parts.addAll([info.model, info.systemName, info.systemVersion]);
      }
    } catch (_) {
      parts.add(Platform.operatingSystem);
    }
    return parts.join('|');
  }

  static String _fallbackId(String name, String model) {
    return EncryptionUtils.sha256Hex('$name|$model');
  }

  static Future<String> _genericDeviceId() async {
    try {
      final info = await _deviceInfo.deviceInfo;
      final data = info.data;
      return EncryptionUtils.sha256Hex(data.toString());
    } catch (_) {
      return EncryptionUtils.sha256Hex(
          Platform.operatingSystem + Platform.operatingSystemVersion);
    }
  }
}
