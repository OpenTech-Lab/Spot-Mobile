String normalizeTag(String raw) =>
    raw.trim().replaceAll('#', '').replaceAll(',', '').toLowerCase();

List<String> normalizeUniqueTags(Iterable<String> rawTags) {
  final normalized = <String>[];
  final seen = <String>{};

  for (final rawTag in rawTags) {
    final tag = normalizeTag(rawTag);
    if (tag.isEmpty || !seen.add(tag)) continue;
    normalized.add(tag);
  }

  return normalized;
}
