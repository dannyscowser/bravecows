// Converts numeric pinyin (e.g., "guo4") to tone-marked form ("guò (4)").
String formatPinyin(String input) {
  return input
      .split(RegExp(r'\s+'))
      .map((s) => _formatSyllable(s))
      .join(' ')
      .trim();
}

String _formatSyllable(String syllable) {
  final match = RegExp(r'([A-Za-züÜvV:]+)([1-5])').firstMatch(syllable);
  if (match == null) return syllable;
  final base = match.group(1) ?? syllable;
  final tone = int.tryParse(match.group(2) ?? '') ?? 5;
  final marked = _applyToneMark(base.toLowerCase(), tone);
  return tone >= 1 && tone <= 4 ? '$marked ($tone)' : marked;
}

String _applyToneMark(String base, int tone) {
  if (tone == 5) return base;
  // Priority vowel selection per pinyin rules.
  int targetIndex = base.indexOf(RegExp(r'[aeo]'));
  if (targetIndex == -1) {
    targetIndex = base.contains('iu') ? base.indexOf('u') : base.indexOf('i');
  }
  if (targetIndex == -1) {
    targetIndex = base.indexOf(RegExp(r'[uv]'));
  }
  if (targetIndex == -1) return base;
  final vowel = base[targetIndex];
  final markedVowel = _toneMap[vowel]?[tone - 1] ?? vowel;
  return base.replaceRange(targetIndex, targetIndex + 1, markedVowel);
}

const Map<String, List<String>> _toneMap = {
  'a': ['ā', 'á', 'ǎ', 'à'],
  'e': ['ē', 'é', 'ě', 'è'],
  'i': ['ī', 'í', 'ǐ', 'ì'],
  'o': ['ō', 'ó', 'ǒ', 'ò'],
  'u': ['ū', 'ú', 'ǔ', 'ù'],
  'v': ['ǖ', 'ǘ', 'ǚ', 'ǜ'],
};
