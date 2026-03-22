import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart' as crypto;
import 'package:pointycastle/export.dart';

/// Encryption and hashing utilities for Citizen Swarm.
/// Uses [crypto] for SHA-256 and [pointycastle] for AES-256-CBC.
class EncryptionUtils {
  EncryptionUtils._();

  // ── SHA-256 ──────────────────────────────────────────────────────────────

  /// Returns the raw SHA-256 digest of [bytes].
  static Uint8List sha256(Uint8List bytes) {
    final digest = crypto.sha256.convert(bytes);
    return Uint8List.fromList(digest.bytes);
  }

  /// Returns the hex-encoded SHA-256 digest of [input] (UTF-8 encoded).
  static String sha256Hex(String input) {
    final bytes = utf8.encode(input);
    final digest = crypto.sha256.convert(bytes);
    return digest.toString();
  }

  /// Returns the hex-encoded SHA-256 digest of raw [bytes].
  static String sha256BytesHex(Uint8List bytes) {
    final digest = crypto.sha256.convert(bytes);
    return digest.toString();
  }

  // ── Random bytes ─────────────────────────────────────────────────────────

  /// Returns [n] cryptographically-random bytes using dart:math SecureRandom.
  static Uint8List randomBytes(int n) {
    final rng = Random.secure();
    return Uint8List.fromList(List.generate(n, (_) => rng.nextInt(256)));
  }

  // ── AES-256-CBC ───────────────────────────────────────────────────────────

  /// Encrypts [data] with [key] (32 bytes) using AES-256-CBC with a random IV.
  /// Returns IV (16 bytes) + ciphertext concatenated.
  static Uint8List aesEncrypt(Uint8List data, Uint8List key) {
    assert(key.length == 32, 'AES-256 key must be 32 bytes');

    final iv = randomBytes(16);
    final cipher = CBCBlockCipher(AESEngine())
      ..init(true, ParametersWithIV(KeyParameter(key), iv));

    final padded = _pkcs7Pad(data, 16);
    final encrypted = Uint8List(padded.length);
    for (var offset = 0; offset < padded.length; offset += 16) {
      cipher.processBlock(padded, offset, encrypted, offset);
    }

    return Uint8List.fromList([...iv, ...encrypted]);
  }

  /// Decrypts [encrypted] (IV + ciphertext) with [key] (32 bytes) using AES-256-CBC.
  static Uint8List aesDecrypt(Uint8List encrypted, Uint8List key) {
    assert(key.length == 32, 'AES-256 key must be 32 bytes');
    assert(encrypted.length >= 16, 'Ciphertext too short');

    final iv = encrypted.sublist(0, 16);
    final ciphertext = encrypted.sublist(16);

    final cipher = CBCBlockCipher(AESEngine())
      ..init(false, ParametersWithIV(KeyParameter(key), iv));

    final decrypted = Uint8List(ciphertext.length);
    for (var offset = 0; offset < ciphertext.length; offset += 16) {
      cipher.processBlock(ciphertext, offset, decrypted, offset);
    }

    return _pkcs7Unpad(decrypted);
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  /// PKCS#7 pads [data] to a multiple of [blockSize].
  static Uint8List _pkcs7Pad(Uint8List data, int blockSize) {
    final padding = blockSize - (data.length % blockSize);
    return Uint8List.fromList([...data, ...List.filled(padding, padding)]);
  }

  /// Removes PKCS#7 padding from [data].
  static Uint8List _pkcs7Unpad(Uint8List data) {
    if (data.isEmpty) return data;
    final padding = data.last;
    if (padding > 16 || padding == 0) return data;
    return data.sublist(0, data.length - padding);
  }

  /// Converts a hex string to a [Uint8List].
  static Uint8List hexToBytes(String hex) {
    final result = Uint8List(hex.length ~/ 2);
    for (var i = 0; i < hex.length; i += 2) {
      result[i ~/ 2] = int.parse(hex.substring(i, i + 2), radix: 16);
    }
    return result;
  }

  /// Converts [bytes] to a lowercase hex string.
  static String bytesToHex(Uint8List bytes) =>
      bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
}
