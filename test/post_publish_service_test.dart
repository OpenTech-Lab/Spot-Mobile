import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:mobile/services/post_publish_service.dart';

void main() {
  test('root threads require at least one normalized category tag', () {
    expect(
      validateThreadCategoryRequirement(replyToId: null, eventTags: const []),
      kMissingCategoryTagMessage,
    );
    expect(
      validateThreadCategoryRequirement(
        replyToId: null,
        eventTags: const ['#', ' , '],
      ),
      kMissingCategoryTagMessage,
    );
  });

  test('root threads accept a normalized category tag', () {
    expect(
      validateThreadCategoryRequirement(
        replyToId: null,
        eventTags: const ['#Tokyo', 'tokyo', 'alert'],
      ),
      isNull,
    );
  });

  test('replies can publish without adding a new category tag', () {
    expect(
      validateThreadCategoryRequirement(
        replyToId: 'parent-event-id',
        eventTags: const [],
      ),
      isNull,
    );
  });

  test('normalizePublishError maps backend category denial to local error', () {
    final normalized = normalizePublishError(
      PostgrestException(
        message: 'missing category tag',
        code: 'P0001',
        details: 'MISSING_CATEGORY_TAG',
        hint: 'Add a category tag before posting a new thread.',
      ),
    );

    expect(normalized, isA<MissingCategoryTagError>());
    expect(
      (normalized as MissingCategoryTagError).message,
      kMissingCategoryTagMessage,
    );
  });

  test(
    'normalizePublishError maps backend daily cap denial to publish denied',
    () {
      final normalized = normalizePublishError(
        PostgrestException(
          message: 'daily thread limit reached',
          code: 'P0001',
          details: 'THREAD_DAILY_LIMIT_REACHED',
          hint:
              'Daily thread limit reached for your current activity level (2/day).',
        ),
      );

      expect(normalized, isA<PublishDeniedError>());
      expect(
        (normalized as PublishDeniedError).code,
        'THREAD_DAILY_LIMIT_REACHED',
      );
      expect(
        normalized.message,
        'Daily thread limit reached for your current activity level (2/day).',
      );
    },
  );

  test('normalizePublishError leaves unrelated backend errors untouched', () {
    final error = PostgrestException(
      message: 'permission denied',
      code: '42501',
      details: 'Forbidden',
    );

    expect(normalizePublishError(error), same(error));
  });
}
