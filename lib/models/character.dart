class Character {
  final String traditional;
  final String simplified;
  final String pinyin;
  final String definitions;
  final double? frequency;
  final bool? isKnown;

  const Character({
    required this.traditional,
    required this.simplified,
    required this.pinyin,
    required this.definitions,
    this.frequency,
    this.isKnown,
  });

  Character copyWith({bool? isKnown}) {
    return Character(
      traditional: traditional,
      simplified: simplified,
      pinyin: pinyin,
      definitions: definitions,
      frequency: frequency,
      isKnown: isKnown ?? this.isKnown,
    );
  }
}
