import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:mobile/core/tag_normalizer.dart';

void main() {
  test('normalizeTag removes spaces, punctuation, and upper-case variants', () {
    expect(normalizeTag('  #Tokyo, '), 'tokyo');
    expect(normalizeTag('AWS Summit Tokyo 2026'), 'awssummittokyo2026');
    expect(normalizeTag(''), '');
  });

  test('normalizeUniqueTags removes blanks and preserves first occurrence', () {
    expect(normalizeUniqueTags(['#Tokyo', 'tokyo,', '  ', 'Shi buya']), [
      'tokyo',
      'shibuya',
    ]);
  });

  test('tag formatter canonicalizes live input and preserves caret offset', () {
    const formatter = CanonicalTagTextInputFormatter();
    const newValue = TextEditingValue(
      text: '#AWS Summit,',
      selection: TextSelection.collapsed(offset: 12),
    );

    final formatted = formatter.formatEditUpdate(
      TextEditingValue.empty,
      newValue,
    );

    expect(formatted.text, 'awssummit');
    expect(formatted.selection.baseOffset, 9);
    expect(formatted.selection.extentOffset, 9);
  });
}
