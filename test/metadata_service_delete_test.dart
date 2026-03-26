import 'package:flutter_test/flutter_test.dart';

import 'package:mobile/features/metadata/metadata_service.dart';

void main() {
  test('resolveDeleteTargetPostId keeps a valid uuid id', () {
    const postId = '123e4567-e89b-12d3-a456-426614174000';

    final resolved = resolveDeleteTargetPostId(
      requestedPostId: postId,
      contentHash: 'hash-1',
      ownedRows: const [],
    );

    expect(resolved, postId);
  });

  test('resolveDeleteTargetPostId falls back to owned row by content hash', () {
    final resolved = resolveDeleteTargetPostId(
      requestedPostId: 'legacy-hash-id',
      contentHash: 'hash-2',
      ownedRows: const [
        {
          'id': '123e4567-e89b-12d3-a456-426614174001',
          'content_hashes': ['hash-1', 'hash-2'],
        },
      ],
    );

    expect(resolved, '123e4567-e89b-12d3-a456-426614174001');
  });

  test('resolveDeleteTargetPostId returns null when no owned row matches', () {
    final resolved = resolveDeleteTargetPostId(
      requestedPostId: 'legacy-hash-id',
      contentHash: 'hash-2',
      ownedRows: const [
        {
          'id': '123e4567-e89b-12d3-a456-426614174001',
          'content_hashes': ['hash-1'],
        },
      ],
    );

    expect(resolved, isNull);
  });
}
