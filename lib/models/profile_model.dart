class ProfileModel {
  const ProfileModel({
    required this.id,
    this.createdAt,
    this.displayName,
    this.legacyPubkey,
    this.legacyNpub,
    this.deviceId,
    this.avatarSeed,
    this.avatarContentHash,
  });

  final String id;
  final DateTime? createdAt;
  final String? displayName;
  final String? legacyPubkey;
  final String? legacyNpub;
  final String? deviceId;
  final String? avatarSeed;
  final String? avatarContentHash;

  factory ProfileModel.fromRow(Map<String, dynamic> row) => ProfileModel(
    id: row['id'].toString(),
    createdAt: row['created_at'] != null
        ? DateTime.parse(row['created_at'].toString()).toUtc()
        : null,
    displayName: row['display_name']?.toString(),
    legacyPubkey: row['legacy_pubkey']?.toString(),
    legacyNpub: row['legacy_npub']?.toString(),
    deviceId: row['device_id']?.toString(),
    avatarSeed: row['avatar_seed']?.toString(),
    avatarContentHash: row['avatar_content_hash']?.toString(),
  );
}
