/// Wallet data model representing the Device-Bound Nostr identity.
/// The private key is a 32-byte secp256k1 key stored in hardware secure storage.
class WalletModel {
  /// 32-byte secp256k1 private key (hex encoded, 64 hex chars)
  final String privateKeyHex;

  /// 32-byte secp256k1 public key x-coordinate (hex encoded, 64 hex chars)
  final String publicKeyHex;

  /// Bech32-encoded Nostr public key (npub1...)
  final String npub;

  /// BIP39 12-word mnemonic for wallet recovery
  final List<String> mnemonic;

  /// Stable hardware device identifier
  final String deviceId;

  /// Whether this wallet has been revoked (migrated away)
  final bool isRevoked;

  /// When this wallet was created
  final DateTime createdAt;

  const WalletModel({
    required this.privateKeyHex,
    required this.publicKeyHex,
    required this.npub,
    required this.mnemonic,
    required this.deviceId,
    required this.isRevoked,
    required this.createdAt,
  });

  Map<String, dynamic> toJson() => {
        'privateKeyHex': privateKeyHex,
        'publicKeyHex': publicKeyHex,
        'npub': npub,
        'mnemonic': mnemonic,
        'deviceId': deviceId,
        'isRevoked': isRevoked,
        'createdAt': createdAt.toIso8601String(),
      };

  factory WalletModel.fromJson(Map<String, dynamic> json) => WalletModel(
        privateKeyHex: json['privateKeyHex'] as String,
        publicKeyHex: json['publicKeyHex'] as String,
        npub: json['npub'] as String,
        mnemonic: List<String>.from(json['mnemonic'] as List),
        deviceId: json['deviceId'] as String,
        isRevoked: json['isRevoked'] as bool? ?? false,
        createdAt: DateTime.parse(json['createdAt'] as String),
      );

  WalletModel copyWith({
    String? privateKeyHex,
    String? publicKeyHex,
    String? npub,
    List<String>? mnemonic,
    String? deviceId,
    bool? isRevoked,
    DateTime? createdAt,
  }) =>
      WalletModel(
        privateKeyHex: privateKeyHex ?? this.privateKeyHex,
        publicKeyHex: publicKeyHex ?? this.publicKeyHex,
        npub: npub ?? this.npub,
        mnemonic: mnemonic ?? this.mnemonic,
        deviceId: deviceId ?? this.deviceId,
        isRevoked: isRevoked ?? this.isRevoked,
        createdAt: createdAt ?? this.createdAt,
      );

  /// Returns a truncated display form of the npub for UI.
  String get npubShort {
    if (npub.length <= 20) return npub;
    return '${npub.substring(0, 10)}...${npub.substring(npub.length - 8)}';
  }

  @override
  String toString() =>
      'WalletModel(npub: $npubShort, deviceId: $deviceId, isRevoked: $isRevoked)';
}
