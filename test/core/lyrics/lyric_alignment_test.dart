import 'package:flutter_test/flutter_test.dart';
import 'package:jianpu_keyboard/core/lyrics/lyric_alignment.dart';
import 'package:jianpu_keyboard/core/models/lyric_line.dart';
import 'package:jianpu_keyboard/core/models/music_token.dart';
import 'package:jianpu_keyboard/core/models/parse_result.dart';
import 'package:jianpu_keyboard/core/models/register.dart';
import 'package:jianpu_keyboard/core/models/score.dart';
import 'package:jianpu_keyboard/core/models/source_position.dart';
import 'package:jianpu_keyboard/core/parser/jianpu_parser.dart';
import 'package:jianpu_keyboard/core/parser/lyric_tokenizer.dart';

void main() {
  const alignment = LyricAlignmentService();
  const tokenizer = LyricTokenizer();
  const parser = JianpuParser();

  Note note(
    int tokenIndex, {
    int line = 1,
    int degree = 3,
    String? lyric,
  }) {
    return Note(
      position: SourcePosition(
        line: line,
        column: 1,
        tokenIndex: tokenIndex,
        rawToken: '$degree',
      ),
      degree: degree,
      register: Register.middle,
      lyric: lyric,
    );
  }

  SourcePosition position(int tokenIndex, String rawToken, {int line = 1}) {
    return SourcePosition(
      line: line,
      column: 1,
      tokenIndex: tokenIndex,
      rawToken: rawToken,
    );
  }

  List<LyricLine> tokenizeLyrics(String text) {
    if (text.isEmpty) {
      return const [];
    }
    final rawLines = text.split(RegExp(r'\r?\n'));
    return [
      for (var i = 0; i < rawLines.length; i++)
        tokenizer.tokenizeLine(rawLines[i], i + 1),
    ];
  }

  List<String?> noteLyrics(Score score) {
    return [
      for (final line in score.lines)
        for (final token in line.tokens)
          if (token is Note) token.lyric,
    ];
  }

  List<Note> notesOf(Score score) {
    return [
      for (final line in score.lines)
        for (final token in line.tokens)
          if (token is Note) token,
    ];
  }

  Score parseScore(String scoreText) {
    final parsed = parser.parse(scoreText: scoreText);
    return (parsed as ParseSuccess).score;
  }

  Score alignText(String scoreText, String lyricsText) {
    return alignment.align(parseScore(scoreText), tokenizeLyrics(lyricsText));
  }

  test('aligns lyrics to consecutive notes', () {
    final score = Score(
      lines: [
        ScoreLine(
          lineNumber: 1,
          tokens: [note(1), note(2), note(3)],
        ),
      ],
    );
    final lyrics = [
      const LyricLine(
        lineNumber: 1,
        tokens: [
          LyricToken(
            line: 1,
            elementIndex: 1,
            rawText: '我',
            isMeasureBar: false,
            syllable: '我',
          ),
          LyricToken(
            line: 1,
            elementIndex: 2,
            rawText: '爱',
            isMeasureBar: false,
            syllable: '爱',
          ),
          LyricToken(
            line: 1,
            elementIndex: 3,
            rawText: '你',
            isMeasureBar: false,
            syllable: '你',
          ),
        ],
      ),
    ];

    final aligned = alignment
        .align(score, lyrics)
        .lines
        .single
        .tokens
        .whereType<Note>()
        .toList();
    expect(aligned.map((item) => item.lyric), ['我', '爱', '你']);
  });

  test('preserves lyric alignment when hold symbols are present', () {
    final score = Score(
      lines: [
        ScoreLine(
          lineNumber: 1,
          tokens: [
            note(1),
            Hold(position: position(2, '-')),
            Hold(position: position(3, '-')),
          ],
        ),
      ],
    );
    final lyrics = [
      const LyricLine(
        lineNumber: 1,
        tokens: [
          LyricToken(
            line: 1,
            elementIndex: 1,
            rawText: '我',
            isMeasureBar: false,
            syllable: '我',
          ),
        ],
      ),
    ];

    final tokens = alignment.align(score, lyrics).lines.single.tokens;
    expect((tokens[0] as Note).lyric, '我');
    expect(tokens[1], isA<Hold>());
    expect(tokens[2], isA<Hold>());
  });

  test('does not consume lyrics for rests', () {
    final score = Score(
      lines: [
        ScoreLine(
          lineNumber: 1,
          tokens: [
            note(1),
            Rest(position: position(2, '0')),
            note(3),
          ],
        ),
      ],
    );
    final lyrics = [
      const LyricLine(
        lineNumber: 1,
        tokens: [
          LyricToken(
            line: 1,
            elementIndex: 1,
            rawText: '我',
            isMeasureBar: false,
            syllable: '我',
          ),
          LyricToken(
            line: 1,
            elementIndex: 2,
            rawText: '爱',
            isMeasureBar: false,
            syllable: '爱',
          ),
        ],
      ),
    ];

    final notes = alignment
        .align(score, lyrics)
        .lines
        .single
        .tokens
        .whereType<Note>()
        .toList();
    expect(notes[0].lyric, '我');
    expect(notes[1].lyric, '爱');
  });

  test('leaves remaining notes without lyrics when lyrics run out', () {
    final score = Score(
      lines: [
        ScoreLine(
          lineNumber: 1,
          tokens: [note(1), note(2), note(3)],
        ),
      ],
    );
    final lyrics = [
      const LyricLine(
        lineNumber: 1,
        tokens: [
          LyricToken(
            line: 1,
            elementIndex: 1,
            rawText: '我',
            isMeasureBar: false,
            syllable: '我',
          ),
        ],
      ),
    ];

    final notes = alignment
        .align(score, lyrics)
        .lines
        .single
        .tokens
        .whereType<Note>()
        .toList();
    expect(notes[0].lyric, '我');
    expect(notes[1].lyric, isNull);
    expect(notes[2].lyric, isNull);
  });

  test('aligns lyrics across score and lyric lines in global order', () {
    final score = Score(
      lines: [
        ScoreLine(
          lineNumber: 1,
          tokens: [note(1, degree: 3), note(2, degree: 4), note(3, degree: 5)],
        ),
        ScoreLine(
          lineNumber: 2,
          tokens: [note(1, line: 2, degree: 6), note(2, line: 2, degree: 7)],
        ),
      ],
    );

    final aligned = alignment.align(score, tokenizeLyrics('我 爱\n你 好 吗'));
    expect(noteLyrics(aligned), ['我', '爱', '你', '好', '吗']);
  });

  test('continues lyrics across multiple score lines from one lyric line', () {
    final score = Score(
      lines: [
        ScoreLine(
          lineNumber: 1,
          tokens: [note(1, degree: 3), note(2, degree: 4)],
        ),
        ScoreLine(
          lineNumber: 2,
          tokens: [note(1, line: 2, degree: 5), note(2, line: 2, degree: 6)],
        ),
        ScoreLine(
          lineNumber: 3,
          tokens: [
            note(1, line: 3, degree: 7),
            note(2, line: 3, degree: 1),
          ],
        ),
      ],
    );

    final aligned = alignment.align(score, tokenizeLyrics('我爱你好吗世界'));
    expect(noteLyrics(aligned), ['我', '爱', '你', '好', '吗', '世']);
  });

  test('does not consume lyrics for a hold among notes', () {
    final score = Score(
      lines: [
        ScoreLine(
          lineNumber: 1,
          tokens: [
            note(1, degree: 3),
            Hold(position: position(2, '-')),
            note(3, degree: 4),
            note(4, degree: 5),
          ],
        ),
      ],
    );

    final aligned = alignment.align(score, tokenizeLyrics('我 爱 你'));
    final tokens = aligned.lines.single.tokens;
    expect((tokens[0] as Note).lyric, '我');
    expect(tokens[1], isA<Hold>());
    expect((tokens[2] as Note).lyric, '爱');
    expect((tokens[3] as Note).lyric, '你');
  });

  test('does not consume lyrics for a rest among notes', () {
    final score = Score(
      lines: [
        ScoreLine(
          lineNumber: 1,
          tokens: [
            note(1, degree: 3),
            Rest(position: position(2, '0')),
            note(3, degree: 4),
            note(4, degree: 5),
          ],
        ),
      ],
    );

    final aligned = alignment.align(score, tokenizeLyrics('我 爱 你'));
    final tokens = aligned.lines.single.tokens;
    expect((tokens[0] as Note).lyric, '我');
    expect(tokens[1], isA<Rest>());
    expect((tokens[2] as Note).lyric, '爱');
    expect((tokens[3] as Note).lyric, '你');
  });

  test('does not consume lyrics for a measure bar', () {
    final score = Score(
      lines: [
        ScoreLine(
          lineNumber: 1,
          tokens: [
            note(1, degree: 3),
            note(2, degree: 4),
            MeasureBar(position: position(3, '|')),
            note(4, degree: 5),
            note(5, degree: 6),
          ],
        ),
      ],
    );

    final aligned = alignment.align(score, tokenizeLyrics('我 爱 你 好'));
    expect(noteLyrics(aligned), ['我', '爱', '你', '好']);
  });

  test('does not reset lyric index when either side wraps to a new line', () {
    final score = Score(
      lines: [
        ScoreLine(
          lineNumber: 1,
          tokens: [note(1, degree: 3), note(2, degree: 4)],
        ),
        ScoreLine(
          lineNumber: 2,
          tokens: [note(1, line: 2, degree: 5), note(2, line: 2, degree: 6)],
        ),
      ],
    );

    final aligned = alignment.align(score, tokenizeLyrics('我\n爱你好吗'));
    expect(noteLyrics(aligned), ['我', '爱', '你', '好']);
  });

  test('leaves unmatched notes without lyrics when lyrics are insufficient',
      () {
    final score = Score(
      lines: [
        ScoreLine(
          lineNumber: 1,
          tokens: [
            note(1, degree: 3),
            note(2, degree: 4),
            note(3, degree: 5),
            note(4, degree: 6),
          ],
        ),
      ],
    );

    final aligned = alignment.align(score, tokenizeLyrics('我 爱'));
    expect(noteLyrics(aligned), ['我', '爱', null, null]);
  });

  test('leaves every note without lyrics when lyrics are empty', () {
    final score = Score(
      lines: [
        ScoreLine(
          lineNumber: 1,
          tokens: [note(1, degree: 3), note(2, degree: 4), note(3, degree: 5)],
        ),
      ],
    );

    final aligned = alignment.align(score, tokenizeLyrics(''));
    expect(noteLyrics(aligned), [null, null, null]);
  });

  test('ignores blank lyric lines without resetting the global index', () {
    final score = Score(
      lines: [
        ScoreLine(
          lineNumber: 1,
          tokens: [note(1, degree: 3), note(2, degree: 4)],
        ),
        ScoreLine(
          lineNumber: 2,
          tokens: [note(1, line: 2, degree: 5), note(2, line: 2, degree: 6)],
        ),
      ],
    );

    final aligned = alignment.align(
      score,
      tokenizeLyrics('我\n\n爱 你 好'),
    );
    expect(noteLyrics(aligned), ['我', '爱', '你', '好']);
  });

  test('aligns ordinary lyrics without marking continuation', () {
    final notes = notesOf(alignText('3 4 5', '我 爱 你'));

    expect(notes.map((note) => note.lyric), ['我', '爱', '你']);
    expect(notes.map((note) => note.isLyricContinuation), [
      false,
      false,
      false,
    ]);
  });

  test('reuses the previous syllable for a single continuation', () {
    final notes = notesOf(alignText('3 2 2', '低 垂 -'));

    expect(notes.map((note) => note.lyric), ['低', '垂', '垂']);
    expect(notes[0].isLyricContinuation, isFalse);
    expect(notes[1].isLyricContinuation, isFalse);
    expect(notes[2].isLyricContinuation, isTrue);
  });

  test('reuses the previous syllable for multiple continuations', () {
    final notes = notesOf(alignText('3 4 5 6', '我 - - -'));

    expect(notes.map((note) => note.lyric), ['我', '我', '我', '我']);
    expect(notes.map((note) => note.isLyricContinuation), [
      false,
      true,
      true,
      true,
    ]);
  });

  test('applies a new syllable after continuations', () {
    final notes = notesOf(alignText('3 4 5', '我 - 爱'));

    expect(notes.map((note) => note.lyric), ['我', '我', '爱']);
    expect(notes.map((note) => note.isLyricContinuation), [
      false,
      true,
      false,
    ]);
  });

  test('does not treat repeated identical characters as continuation', () {
    final notes = notesOf(alignText('3 4', '黑 黑'));

    expect(notes.map((note) => note.lyric), ['黑', '黑']);
    expect(notes[0].isLyricContinuation, isFalse);
    expect(notes[1].isLyricContinuation, isFalse);
  });

  test('continues a syllable across a measure bar', () {
    final aligned = alignText('3 | 0 4\n5', '我 -\n爱');
    final notes = notesOf(aligned);

    expect(notes.map((note) => note.lyric), ['我', '我', '爱']);
    expect(notes[1].isLyricContinuation, isTrue);
    expect(aligned.lines.first.tokens[1], isA<MeasureBar>());
  });

  test('continues a syllable across line breaks without resetting', () {
    final notes = notesOf(
      alignText('3 4\n5 6\n7', '我 爱\n你 -\n好'),
    );

    expect(notes.map((note) => note.lyric), ['我', '爱', '你', '你', '好']);
    expect(notes.map((note) => note.isLyricContinuation), [
      false,
      false,
      false,
      true,
      false,
    ]);
  });

  test('continues a syllable across a rest', () {
    final aligned = alignText('3 0 4', '我 -');
    final tokens = aligned.lines.single.tokens;
    final notes = notesOf(aligned);

    expect(tokens[1], isA<Rest>());
    expect(notes.map((note) => note.lyric), ['我', '我']);
    expect(notes[1].isLyricContinuation, isTrue);
  });

  test('continues a syllable across a score hold', () {
    final aligned = alignText('3 - 4', '我 -');
    final tokens = aligned.lines.single.tokens;
    final notes = notesOf(aligned);

    expect(tokens[1], isA<Hold>());
    expect(notes.map((note) => note.lyric), ['我', '我']);
    expect(notes[1].isLyricContinuation, isTrue);
  });

  test(
      'skips a leading continuation so the next syllable aligns to the first note',
      () {
    final notes = notesOf(alignText('3 4', '- 我'));

    expect(notes.map((note) => note.lyric), ['我', null]);
    expect(notes[0].isLyricContinuation, isFalse);
    expect(notes[1].isLyricContinuation, isFalse);
  });

  test('skips multiple leading continuations without consuming notes', () {
    final notes = notesOf(alignText('3 4', '- - 我'));

    expect(notes.map((note) => note.lyric), ['我', null]);
    expect(notes.map((note) => note.isLyricContinuation), [false, false]);
  });

  test('keeps 垂 on the last notes of the 虫儿飞 fragment', () {
    final notes = notesOf(
      alignText(
        '3 3 3 4 5 | 3 2 2 -',
        '黑 黑 的 天 空 | 低 垂 -',
      ),
    );

    expect(
      notes.map((note) => note.lyric),
      ['黑', '黑', '的', '天', '空', '低', '垂', '垂'],
    );
    expect(notes[6].isLyricContinuation, isFalse);
    expect(notes[7].isLyricContinuation, isTrue);
  });

  test('starts the next 虫儿飞 line at 亮 instead of consuming it early', () {
    final notes = notesOf(
      alignText(
        '3 3 3 4 5 | 3 2 2 -\n'
            '1 1 1 2 3 | 3 7 7 -',
        '黑 黑 的 天 空 | 低 垂 -\n'
            '亮 亮 的 繁 星 | 相 随 -',
      ),
    );

    expect(
      notes.map((note) => note.lyric),
      [
        '黑',
        '黑',
        '的',
        '天',
        '空',
        '低',
        '垂',
        '垂',
        '亮',
        '亮',
        '的',
        '繁',
        '星',
        '相',
        '随',
        '随',
      ],
    );
    expect(notes[7].lyric, '垂');
    expect(notes[7].isLyricContinuation, isTrue);
    expect(notes[8].lyric, '亮');
    expect(notes[8].isLyricContinuation, isFalse);
    expect(notes[15].lyric, '随');
    expect(notes[15].isLyricContinuation, isTrue);
  });

  test('keeps 1-to-1 global alignment when no continuation is written', () {
    final notes = notesOf(alignText('3 2 2\n4 5', '低 垂\n亮 空'));

    expect(notes.map((note) => note.lyric), ['低', '垂', '亮', '空', null]);
    expect(notes.map((note) => note.isLyricContinuation), [
      false,
      false,
      false,
      false,
      false,
    ]);
  });

  test('continues a syllable across lines then aligns the next syllable', () {
    final notes = notesOf(alignText('3 4\n5 6', '我 -\n爱'));

    expect(notes.map((note) => note.lyric), ['我', '我', '爱', null]);
    expect(notes.map((note) => note.isLyricContinuation), [
      false,
      true,
      false,
      false,
    ]);
  });
}
