import 'package:flutter_test/flutter_test.dart';

import 'package:mobile/models/follow_stats.dart';

void main() {
  test('FollowStats.fromRpcRow parses numeric and boolean fields', () {
    final stats = FollowStats.fromRpcRow({
      'follower_count': '7',
      'following_count': 3,
      'is_following_by_me': 'true',
    });

    expect(stats.followerCount, 7);
    expect(stats.followingCount, 3);
    expect(stats.isFollowingByMe, isTrue);
  });
}
