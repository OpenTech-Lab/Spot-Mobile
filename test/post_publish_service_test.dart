import 'package:flutter_test/flutter_test.dart';

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
}
