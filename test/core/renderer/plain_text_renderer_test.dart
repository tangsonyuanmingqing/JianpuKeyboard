import 'package:flutter_test/flutter_test.dart';
import 'package:jianpu_keyboard/core/mapping/keyboard_mapping.dart';
import 'package:jianpu_keyboard/core/models/music_token.dart';
import 'package:jianpu_keyboard/core/models/register.dart';
import 'package:jianpu_keyboard/core/models/score.dart';
import 'package:jianpu_keyboard/core/models/source_position.dart';
import 'package:jianpu_keyboard/core/renderer/plain_text_renderer.dart';

void main() {
  const renderer = PlainTextRenderer();
  const mapping = KeyboardMapping();

  Note note(
    int degree,
    Register register,
    int elementIndex, {
    String? lyric,
    bool isLyricContinuation = false,
  }) {
    return Note(
      position: SourcePosition(
        line: 1,
        column: 1,
        tokenIndex: elementIndex,
        rawToken: '$degree',
      ),
      degree: degree,
      register: register,
      lyric: lyric,
      isLyricContinuation: isLyricContinuation,
    );
  }

  test('renders mapped notes as keyboard letters', () {
    final score = mapping.apply(
      Score(
        lines: [
          ScoreLine(
            lineNumber: 1,
            tokens: [
              note(3, Register.middle, 1),
              note(4, Register.middle, 2),
              note(5, Register.middle, 3),
            ],
          ),
        ],
      ),
    );
    expect(renderer.render(score), 'D F G');
  });

  test('renders lyrics under notes and preserves measure bars', () {
    final score = mapping.apply(
      Score(
        lines: [
          ScoreLine(
            lineNumber: 1,
            tokens: [
              note(3, Register.middle, 1, lyric: '我'),
              note(4, Register.middle, 2, lyric: '爱'),
              const MeasureBar(
                position: SourcePosition(
                  line: 1,
                  column: 1,
                  tokenIndex: 3,
                  rawToken: '|',
                ),
              ),
              note(5, Register.middle, 4, lyric: '你'),
            ],
          ),
        ],
      ),
    );
    expect(renderer.render(score), 'D F | G\n我 爱 | 你');
  });

  test('renders a continuation note as a hyphen', () {
    final score = mapping.apply(
      Score(
        lines: [
          ScoreLine(
            lineNumber: 1,
            tokens: [
              note(3, Register.middle, 1, lyric: '低'),
              note(2, Register.middle, 2, lyric: '垂'),
              note(
                2,
                Register.middle,
                3,
                lyric: '垂',
                isLyricContinuation: true,
              ),
              const Hold(
                position: SourcePosition(
                  line: 1,
                  column: 1,
                  tokenIndex: 4,
                  rawToken: '-',
                ),
              ),
            ],
          ),
        ],
      ),
    );

    expect(renderer.render(score), 'D S S -\n低 垂 -');
    expect(
      score.lines.single.tokens.whereType<Note>().last.isLyricContinuation,
      isTrue,
    );
  });

  test('renders repeated syllables that are not continuations as themselves',
      () {
    final score = mapping.apply(
      Score(
        lines: [
          ScoreLine(
            lineNumber: 1,
            tokens: [
              note(3, Register.middle, 1, lyric: '黑'),
              note(3, Register.middle, 2, lyric: '黑'),
            ],
          ),
        ],
      ),
    );

    expect(renderer.render(score), 'D D\n黑 黑');
  });
}
