import 'package:flutter_test/flutter_test.dart';
import 'package:jianpu_keyboard/core/mapping/keyboard_mapping.dart';
import 'package:jianpu_keyboard/core/models/music_token.dart';
import 'package:jianpu_keyboard/core/models/register.dart';
import 'package:jianpu_keyboard/core/models/score.dart';
import 'package:jianpu_keyboard/core/models/source_position.dart';
import 'package:jianpu_keyboard/core/renderer/display_width.dart';
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

  SourcePosition pos(int tokenIndex, String rawToken) {
    return SourcePosition(
      line: 1,
      column: 1,
      tokenIndex: tokenIndex,
      rawToken: rawToken,
    );
  }

  String render(List<MusicToken> tokens) {
    return renderer.render(
      mapping.apply(
        Score(
          lines: [
            ScoreLine(lineNumber: 1, tokens: tokens),
          ],
        ),
      ),
    );
  }

  int displayOffset(String row, int charIndex) {
    return displayWidth(row.substring(0, charIndex));
  }

  test('renders mapped notes as keyboard letters', () {
    expect(
      render([
        note(3, Register.middle, 1),
        note(4, Register.middle, 2),
        note(5, Register.middle, 3),
      ]),
      'Ｄ Ｆ Ｇ',
    );
  });

  test('renders one syllable under each note with CJK column width', () {
    expect(
      render([
        note(3, Register.middle, 1, lyric: '我'),
        note(4, Register.middle, 2, lyric: '爱'),
        note(5, Register.middle, 3, lyric: '你'),
      ]),
      'Ｄ Ｆ Ｇ\n我 爱 你',
    );
  });

  test(
      'renders lyrics under notes and preserves measure bars in the same column',
      () {
    final output = render([
      note(3, Register.middle, 1, lyric: '我'),
      note(4, Register.middle, 2, lyric: '爱'),
      MeasureBar(position: pos(3, '|')),
      note(5, Register.middle, 3, lyric: '你'),
    ]);
    expect(output, 'Ｄ Ｆ | Ｇ\n我 爱 | 你');

    final lines = output.split('\n');
    expect(
      displayOffset(lines[0], lines[0].indexOf('|')),
      displayOffset(lines[1], lines[1].indexOf('|')),
    );
  });

  test('renders a continuation note as a hyphen', () {
    final output = render([
      note(3, Register.middle, 1, lyric: '低'),
      note(2, Register.middle, 2, lyric: '垂'),
      note(
        2,
        Register.middle,
        3,
        lyric: '垂',
        isLyricContinuation: true,
      ),
      Hold(position: pos(4, '-')),
    ]);

    expect(output, 'Ｄ Ｓ Ｓ -\n低 垂 -');

    final lines = output.split('\n');
    final letter = lines[0];
    final lyrics = lines[1];
    final thirdS = letter.lastIndexOf('Ｓ');
    final continuation = lyrics.indexOf('-');
    final hold = letter.lastIndexOf('-');

    expect(displayOffset(letter, thirdS), displayOffset(lyrics, continuation));
    expect(
      displayOffset(letter, hold),
      isNot(displayOffset(lyrics, continuation)),
    );
  });

  test('does not infer continuation from repeated identical characters', () {
    expect(
      render([
        note(3, Register.middle, 1, lyric: '黑'),
        note(3, Register.middle, 2, lyric: '黑'),
      ]),
      'Ｄ Ｄ\n黑 黑',
    );
  });

  test('keeps a rest column so later lyrics do not shift left', () {
    final output = render([
      note(3, Register.middle, 1, lyric: '我'),
      Rest(position: pos(2, '0')),
      note(4, Register.middle, 3, lyric: '爱'),
      note(5, Register.middle, 4, lyric: '你'),
    ]);
    expect(output, 'Ｄ    Ｆ Ｇ\n我    爱 你');

    final lines = output.split('\n');
    expect(displayOffset(lines[1], lines[1].indexOf('爱')), 6);
    expect(displayOffset(lines[0], lines[0].indexOf('Ｆ')), 6);
  });

  test('keeps a score hold column without a lyric', () {
    expect(
      render([
        note(3, Register.middle, 1, lyric: '我'),
        note(4, Register.middle, 2, lyric: '爱'),
        note(5, Register.middle, 3, lyric: '你'),
        Hold(position: pos(4, '-')),
      ]),
      'Ｄ Ｆ Ｇ -\n我 爱 你',
    );
  });

  test('keeps unmatched notes in their original columns', () {
    expect(
      render([
        note(3, Register.middle, 1, lyric: '我'),
        note(4, Register.middle, 2, lyric: '爱'),
        note(5, Register.middle, 3),
        note(6, Register.middle, 4),
      ]),
      'Ｄ Ｆ Ｇ Ｈ\n我 爱',
    );
  });

  test('uses CJK display width rather than String.length', () {
    final output = render([
      note(3, Register.middle, 1, lyric: '我'),
      note(4, Register.middle, 2, lyric: '爱'),
    ]);
    expect(output, 'Ｄ Ｆ\n我 爱');
    expect('我'.length, 1);
    expect(displayWidth('我'), 2);
    expect(displayWidth('Ｄ'), 2);
    expect(output.split('\n').first.startsWith('Ｄ '), isTrue);
  });
}
