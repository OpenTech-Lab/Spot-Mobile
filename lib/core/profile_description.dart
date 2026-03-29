const int maxProfileDescriptionWords = 100;

class ProfileDescriptionTooLongError implements Exception {
  ProfileDescriptionTooLongError(this.wordCount);

  final int wordCount;

  String get message =>
      'Description must be $maxProfileDescriptionWords words or fewer.';

  @override
  String toString() => message;
}

String? normalizeProfileDescription(String raw) {
  final normalized = raw.replaceAll(RegExp(r'\s+'), ' ').trim();
  return normalized.isEmpty ? null : normalized;
}

int countProfileDescriptionWords(String raw) {
  final normalized = normalizeProfileDescription(raw);
  if (normalized == null) return 0;
  return RegExp(r'\S+').allMatches(normalized).length;
}

String? validateProfileDescription(String raw) {
  final wordCount = countProfileDescriptionWords(raw);
  if (wordCount > maxProfileDescriptionWords) {
    throw ProfileDescriptionTooLongError(wordCount);
  }
  return normalizeProfileDescription(raw);
}
