import 'package:flutter_test/flutter_test.dart';

import 'package:mobile/core/tag_normalizer.dart';

void main() {
  test('normalizeTag trims punctuation and lowercases values', () {
    expect(normalizeTag('  #Tokyo, '), 'tokyo');
    expect(normalizeTag(''), '');
  });

  test('normalizeUniqueTags removes blanks and preserves first occurrence', () {
    expect(normalizeUniqueTags(['#Tokyo', 'tokyo,', '  ', 'Shibuya']), [
      'tokyo',
      'shibuya',
    ]);
  });
}
