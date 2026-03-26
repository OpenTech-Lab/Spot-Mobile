class FollowStats {
  const FollowStats({
    required this.followerCount,
    required this.followingCount,
    this.isFollowingByMe = false,
  });

  const FollowStats.empty()
    : followerCount = 0,
      followingCount = 0,
      isFollowingByMe = false;

  final int followerCount;
  final int followingCount;
  final bool isFollowingByMe;

  factory FollowStats.fromRpcRow(Map<String, dynamic> row) => FollowStats(
    followerCount: _toInt(row['follower_count']),
    followingCount: _toInt(row['following_count']),
    isFollowingByMe: _toBool(row['is_following_by_me']),
  );

  static int _toInt(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '') ?? 0;
  }

  static bool _toBool(dynamic value) {
    if (value is bool) return value;
    final normalized = value?.toString().trim().toLowerCase();
    return normalized == 'true' || normalized == 't' || normalized == '1';
  }
}
