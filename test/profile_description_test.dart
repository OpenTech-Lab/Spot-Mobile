import 'package:flutter_test/flutter_test.dart';

import 'package:mobile/core/profile_description.dart';

void main() {
  test('normalizeProfileDescription trims and collapses whitespace', () {
    expect(
      normalizeProfileDescription('  Citizen   reporter\nin  Tokyo  '),
      'Citizen reporter in Tokyo',
    );
    expect(normalizeProfileDescription('   '), isNull);
  });

  test('validateProfileDescription allows 100 words and rejects 101', () {
    final oneHundredWords = List.filled(100, 'word').join(' ');
    final oneHundredOneWords = List.filled(101, 'word').join(' ');

    expect(validateProfileDescription(oneHundredWords), oneHundredWords);
    expect(
      () => validateProfileDescription(oneHundredOneWords),
      throwsA(isA<ProfileDescriptionTooLongError>()),
    );
  });
}
