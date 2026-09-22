import 'package:flutter_test/flutter_test.dart';
import 'package:jianpu_keyboard/core/mapping/keyboard_mapping.dart';
import 'package:jianpu_keyboard/core/models/music_token.dart';
import 'package:jianpu_keyboard/core/models/register.dart';
import 'package:jianpu_keyboard/core/models/score.dart';
import 'package:jianpu_keyboard/core/models/source_position.dart';
import 'package:jianpu_keyboard/core/renderer/share_image_text_renderer.dart';

void main() {
  const renderer = ShareImageTextRenderer(maxCellsPerRow: 3);

  Note note(int degree, int index, String lyric) => Note(
        position: SourcePosition(
          line: 1,
          column: index,
          tokenIndex: index,
          rawToken: '$degree',
        ),
        degree: degree,
        register: Register.middle,
        lyric: lyric,
      );

  test('wraps only between cells and repeats the aligned lyric row', () {
    final score = const KeyboardMapping().apply(
      Score(lines: [
        ScoreLine(
          lineNumber: 1,
          tokens: [
            note(3, 1, '我'),
            note(4, 2, '爱'),
            note(5, 3, '你'),
            note(6, 4, '和'),
            note(7, 5, '他'),
          ],
        ),
      ]),
    );

    expect(renderer.render(score), 'D  F  G\n我 爱 你\nH  J\n和 他');
  });
}
