class PostingQuotaStatus {
  const PostingQuotaStatus({
    required this.accountAgeDays,
    required this.currentTierName,
    required this.threadLimitPerDay,
    required this.replyLimitPerDay,
    required this.threadCountToday,
    required this.replyCountToday,
    required this.threadRemainingToday,
    required this.replyRemainingToday,
    required this.isPostingBlocked,
    this.postingBlockReason,
    required this.resetsAt,
  });

  final int accountAgeDays;
  final String currentTierName;
  final int threadLimitPerDay;
  final int replyLimitPerDay;
  final int threadCountToday;
  final int replyCountToday;
  final int threadRemainingToday;
  final int replyRemainingToday;
  final bool isPostingBlocked;
  final String? postingBlockReason;
  final DateTime resetsAt;

  factory PostingQuotaStatus.fromRpcRow(Map<String, dynamic> row) {
    return PostingQuotaStatus(
      accountAgeDays: _toInt(row['account_age_days']),
      currentTierName: _toRequiredString(row['current_tier_name']),
      threadLimitPerDay: _toInt(row['thread_limit_per_day']),
      replyLimitPerDay: _toInt(row['reply_limit_per_day']),
      threadCountToday: _toInt(row['thread_count_today']),
      replyCountToday: _toInt(row['reply_count_today']),
      threadRemainingToday: _toInt(row['thread_remaining_today']),
      replyRemainingToday: _toInt(row['reply_remaining_today']),
      isPostingBlocked: _toBool(row['is_posting_blocked']),
      postingBlockReason: _toNullableString(row['posting_block_reason']),
      resetsAt: _toDateTime(row['resets_at']),
    );
  }

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

  static String _toRequiredString(dynamic value) {
    final normalized = value?.toString().trim() ?? '';
    if (normalized.isEmpty) {
      throw const FormatException('Missing required posting quota string');
    }
    return normalized;
  }

  static String? _toNullableString(dynamic value) {
    final normalized = value?.toString().trim();
    if (normalized == null || normalized.isEmpty) {
      return null;
    }
    return normalized;
  }

  static DateTime _toDateTime(dynamic value) {
    if (value is DateTime) return value;
    return DateTime.parse(value.toString());
  }
}
