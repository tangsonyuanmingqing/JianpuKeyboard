/// Identifies a user-authored score/lyric segment in the structured input.
///
/// A group is one `[谱]` section and its optional following `[词]` section.
/// A sentence is split by `//`; a row is split by `;` or a physical newline.
class InputSegment {
  final int group;
  final int sentence;
  final int row;

  const InputSegment({
    required this.group,
    required this.sentence,
    required this.row,
  });

  @override
  bool operator ==(Object other) =>
      other is InputSegment &&
      other.group == group &&
      other.sentence == sentence &&
      other.row == row;

  @override
  int get hashCode => Object.hash(group, sentence, row);

  String get label => '第 $group 组，第 $sentence 句，第 $row 行';
}
