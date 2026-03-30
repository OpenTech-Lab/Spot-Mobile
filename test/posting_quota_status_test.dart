import 'package:flutter_test/flutter_test.dart';

import 'package:mobile/models/posting_quota_status.dart';

void main() {
  test('PostingQuotaStatus.fromRpcRow parses quota fields', () {
    final status = PostingQuotaStatus.fromRpcRow({
      'account_age_days': '14',
      'current_tier_name': 'active',
      'thread_limit_per_day': 5,
      'reply_limit_per_day': '12',
      'thread_count_today': '2',
      'reply_count_today': 3,
      'thread_remaining_today': '3',
      'reply_remaining_today': 9,
      'is_posting_blocked': 'false',
      'posting_block_reason': null,
      'resets_at': '2026-03-31T00:00:00Z',
    });

    expect(status.accountAgeDays, 14);
    expect(status.currentTierName, 'active');
    expect(status.threadLimitPerDay, 5);
    expect(status.replyLimitPerDay, 12);
    expect(status.threadCountToday, 2);
    expect(status.replyCountToday, 3);
    expect(status.threadRemainingToday, 3);
    expect(status.replyRemainingToday, 9);
    expect(status.isPostingBlocked, isFalse);
    expect(status.postingBlockReason, isNull);
    expect(status.resetsAt, DateTime.parse('2026-03-31T00:00:00Z'));
  });
}
