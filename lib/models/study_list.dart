class StudyList {
  final int id;
  final String name;
  final String? emoji;
  final bool isSystem;
  final int? rangeStart;
  final int? rangeEnd;

  const StudyList({
    required this.id,
    required this.name,
    this.emoji,
    this.isSystem = false,
    this.rangeStart,
    this.rangeEnd,
  });

  StudyList copyWith({
    int? id,
    String? name,
    String? emoji,
    bool? isSystem,
    int? rangeStart,
    int? rangeEnd,
  }) {
    return StudyList(
      id: id ?? this.id,
      name: name ?? this.name,
      emoji: emoji ?? this.emoji,
      isSystem: isSystem ?? this.isSystem,
      rangeStart: rangeStart ?? this.rangeStart,
      rangeEnd: rangeEnd ?? this.rangeEnd,
    );
  }
}
