class ProfileModel {
  const ProfileModel({
    required this.id,
    this.createdAt,
    this.displayName,
    this.description,
    this.legacyPubkey,
    this.legacyNpub,
    this.deviceId,
    this.avatarSeed,
    this.avatarContentHash,
    this.areThreadsPublic = true,
    this.areRepliesPublic = true,
    this.isFootprintMapPublic = false,
  });

  final String id;
  final DateTime? createdAt;
  final String? displayName;
  final String? description;
  final String? legacyPubkey;
  final String? legacyNpub;
  final String? deviceId;
  final String? avatarSeed;
  final String? avatarContentHash;
  final bool areThreadsPublic;
  final bool areRepliesPublic;
  final bool isFootprintMapPublic;

  factory ProfileModel.fromRow(Map<String, dynamic> row) => ProfileModel(
    id: row['id'].toString(),
    createdAt: row['created_at'] != null
        ? DateTime.parse(row['created_at'].toString()).toUtc()
        : null,
    displayName: row['display_name']?.toString(),
    description: row['description']?.toString(),
    legacyPubkey: row['legacy_pubkey']?.toString(),
    legacyNpub: row['legacy_npub']?.toString(),
    deviceId: row['device_id']?.toString(),
    avatarSeed: row['avatar_seed']?.toString(),
    avatarContentHash: row['avatar_content_hash']?.toString(),
    areThreadsPublic: _toBool(row['threads_public'], fallback: true),
    areRepliesPublic: _toBool(row['replies_public'], fallback: true),
    isFootprintMapPublic: _toBool(row['footprint_map_public'], fallback: false),
  );

  static bool _toBool(dynamic value, {required bool fallback}) {
    if (value is bool) return value;
    final normalized = value?.toString().trim().toLowerCase();
    if (normalized == 'true' || normalized == 't' || normalized == '1') {
      return true;
    }
    if (normalized == 'false' || normalized == 'f' || normalized == '0') {
      return false;
    }
    return fallback;
  }
}
