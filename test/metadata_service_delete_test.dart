import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:mobile/features/metadata/metadata_service.dart';

void main() {
  test('isDeleteAlreadyGoneError matches the soft-delete not-found case', () {
    final error = PostgrestException(
      message: 'post not found for deletion',
      code: 'P0001',
      details: 'Bad Request',
    );

    expect(isDeleteAlreadyGoneError(error), isTrue);
  });

  test('isDeleteAlreadyGoneError ignores other Postgrest errors', () {
    final error = PostgrestException(
      message: 'row level security violation',
      code: '42501',
      details: 'Forbidden',
    );

    expect(isDeleteAlreadyGoneError(error), isFalse);
  });

  test('buildSoftDeletePostParams keeps non-empty delete inputs', () {
    const postId = '123e4567-e89b-12d3-a456-426614174000';
    final params = buildSoftDeletePostParams(
      requestedPostId: postId,
      contentHash: 'hash-1',
    );

    expect(params, {'p_requested_post_id': postId, 'p_content_hash': 'hash-1'});
  });

  test('buildSoftDeletePostParams drops empty values after trimming', () {
    final params = buildSoftDeletePostParams(
      requestedPostId: 'legacy-hash-id',
      contentHash: '   ',
    );

    expect(params, {'p_requested_post_id': 'legacy-hash-id'});
  });
}
