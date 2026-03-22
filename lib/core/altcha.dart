import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:mobile/core/encryption.dart';

/// ALTCHA-compatible client-side proof-of-work.
///
/// Protocol (https://altcha.org/docs/specification/):
///   1. Generate a random [salt] and a secret [_answer].
///   2. [challenge] = SHA-256(salt + answer).
///   3. Client iterates n = 0 … maxNumber until SHA-256(salt+n) == challenge.
///   4. Verify that the found n reproduces the same hash.
///
/// The client-side-only variant omits the HMAC signature — the challenge and
/// solution are both produced on-device.  The purpose is to impose ~50 k hash
/// operations on every cold start, which is trivial for a human but meaningful
/// overhead for a bot scripting mass account creation / relay spam.
class AltchaService {
  AltchaService._();

  /// Average iterations required ≈ maxNumber / 2 ≈ 50 000.
  static const int _maxNumber = 100000;

  /// Generates a fresh challenge.  Call this on the main isolate.
  static AltchaChallenge generate() {
    final rng = Random.secure();
    // 12 random bytes → 24-hex-char salt
    final saltBytes = List.generate(12, (_) => rng.nextInt(256));
    final salt =
        saltBytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
    final answer = rng.nextInt(_maxNumber);
    final challenge = EncryptionUtils.sha256Hex('$salt$answer');
    return AltchaChallenge(
        salt: salt, challenge: challenge, maxNumber: _maxNumber);
  }

  /// Solves [c] in a background isolate.  Returns null only if maxNumber is
  /// exhausted without a match (should never happen for a self-generated challenge).
  static Future<int?> solve(AltchaChallenge c) =>
      compute(_solveIsolate, c);

  /// Verifies that [number] is the correct solution to [challenge].
  static bool verify(AltchaChallenge challenge, int number) =>
      EncryptionUtils.sha256Hex('${challenge.salt}$number') ==
      challenge.challenge;
}

/// Top-level isolate entry point for [compute] — must not be a closure.
int? _solveIsolate(AltchaChallenge c) {
  for (var n = 0; n <= c.maxNumber; n++) {
    if (EncryptionUtils.sha256Hex('${c.salt}$n') == c.challenge) return n;
  }
  return null;
}

/// Immutable value object passed between isolates.
class AltchaChallenge {
  const AltchaChallenge({
    required this.salt,
    required this.challenge,
    required this.maxNumber,
  });

  final String salt;
  final String challenge;
  final int maxNumber;
}
