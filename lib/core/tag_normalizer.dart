import 'package:flutter/services.dart';

final RegExp _tagNoisePattern = RegExp(r'[\s#,]+');

String normalizeTag(String raw) =>
    raw.replaceAll(_tagNoisePattern, '').toLowerCase();

int _normalizedSelectionOffset(String raw, int offset) {
  if (offset <= 0) return 0;
  if (offset >= raw.length) return normalizeTag(raw).length;
  return normalizeTag(raw.substring(0, offset)).length;
}

class CanonicalTagTextInputFormatter extends TextInputFormatter {
  const CanonicalTagTextInputFormatter();

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final normalizedText = normalizeTag(newValue.text);
    if (normalizedText == newValue.text) return newValue;

    final baseOffset = _normalizedSelectionOffset(
      newValue.text,
      newValue.selection.baseOffset,
    );
    final extentOffset = _normalizedSelectionOffset(
      newValue.text,
      newValue.selection.extentOffset,
    );

    return TextEditingValue(
      text: normalizedText,
      selection: TextSelection(
        baseOffset: baseOffset,
        extentOffset: extentOffset,
      ),
      composing: TextRange.empty,
    );
  }
}

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
