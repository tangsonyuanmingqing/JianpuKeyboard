import '../models/lyric_line.dart';
import '../models/input_segment.dart';
import '../models/music_token.dart';
import '../models/parse_error.dart';
import '../models/parse_result.dart';
import '../models/register.dart';
import '../models/score.dart';
import '../models/source_position.dart';
import '../models/validation_message.dart';
import '../syntax/jianpu_syntax.dart';
import 'jianpu_tokenizer.dart';
import 'lyric_tokenizer.dart';

/// Parses Jianpu text into a structured [Score].
///
/// Accepts the standard `[谱]` / `[词]` document, or a bare score without headers.
class JianpuParser {
  static final _notePattern = RegExp(r"^([1-7])([,']?)$");

  final JianpuTokenizer _tokenizer;
  final LyricTokenizer _lyricTokenizer;

  const JianpuParser({
    JianpuTokenizer tokenizer = const JianpuTokenizer(),
    LyricTokenizer lyricTokenizer = const LyricTokenizer(),
  })  : _tokenizer = tokenizer,
        _lyricTokenizer = lyricTokenizer;

  /// Parses [scoreText] as score (or a full document) and optional [lyricsText].
  ParseResult parse({
    required String scoreText,
    String lyricsText = '',
  }) {
    final sections = _usesStructuredSyntax(scoreText, lyricsText)
        ? _splitStructuredSections(scoreText, lyricsText)
        : _splitSections(scoreText, lyricsText);
    if (sections.errors.isNotEmpty) {
      return ParseFailure(sections.errors);
    }
    final errors = <ParseError>[];
    final scoreLines = <ScoreLine>[];

    for (final line in sections.scoreLines) {
      final tokens = <MusicToken>[];
      for (final raw in _tokenizer.tokenizeLine(
        line.text,
        line.number,
        columnOffset: line.columnOffset,
      )) {
        final token = _classifyScoreToken(raw, errors);
        if (token != null) {
          tokens.add(token);
        }
      }
      if (tokens.isNotEmpty) {
        scoreLines.add(
          ScoreLine(
            lineNumber: line.number,
            tokens: tokens,
            segment: line.segment,
          ),
        );
      }
    }

    if (errors.isNotEmpty) {
      return ParseFailure(errors);
    }

    final lyricLines = <LyricLine>[];
    for (final line in sections.lyricLines) {
      final lyricLine = _lyricTokenizer.tokenizeLine(
        line.text,
        line.number,
        segment: line.segment,
      );
      if (lyricLine.tokens.isNotEmpty) {
        lyricLines.add(lyricLine);
      }
    }

    return ParseSuccess(
      score: Score(lines: scoreLines),
      lyricLines: lyricLines,
      inputWarnings: sections.inputWarnings,
    );
  }

  MusicToken? _classifyScoreToken(RawToken raw, List<ParseError> errors) {
    final position = SourcePosition(
      line: raw.line,
      column: raw.column,
      tokenIndex: raw.tokenIndex,
      rawToken: raw.text,
    );

    switch (raw.text) {
      case JianpuSyntax.measureBar:
        return MeasureBar(position: position);
      case JianpuSyntax.holdSymbol:
        return Hold(position: position);
      case JianpuSyntax.restSymbol:
        return Rest(position: position);
    }

    final noteMatch = _notePattern.firstMatch(raw.text);
    if (noteMatch != null) {
      return Note(
        position: position,
        degree: int.parse(noteMatch.group(1)!),
        register: _registerFor(noteMatch.group(2)!),
      );
    }

    errors.add(
      ParseError.unrecognized(
        line: raw.line,
        column: raw.column,
        tokenIndex: raw.tokenIndex,
        token: raw.text,
      ),
    );
    return null;
  }

  Register _registerFor(String marker) {
    switch (marker) {
      case "'":
        return Register.high;
      case ',':
        return Register.low;
      default:
        return Register.middle;
    }
  }

  _DocumentSections _splitSections(String scoreText, String lyricsText) {
    final scoreSourceLines = _numberedLines(scoreText);
    if (_containsHeader(scoreSourceLines)) {
      final extracted = _extractHeaderedDocument(scoreSourceLines);
      if (extracted.lyricLines.isEmpty && lyricsText.trim().isNotEmpty) {
        return _DocumentSections(
          scoreLines: extracted.scoreLines,
          lyricLines: _contentLines(_numberedLines(lyricsText)),
        );
      }
      return _DocumentSections(
        scoreLines: extracted.scoreLines,
        lyricLines: extracted.lyricLines,
        inputWarnings: [
          if (extracted.lyricLines.isNotEmpty && lyricsText.trim().isNotEmpty)
            const ValidationMessage(
              line: 0,
              message: '已忽略独立歌词框：文档内已有 [词] 区块。',
            ),
        ],
      );
    }

    return _DocumentSections(
      scoreLines: _contentLines(scoreSourceLines),
      lyricLines: _contentLines(_numberedLines(lyricsText)),
    );
  }

  bool _usesStructuredSyntax(String scoreText, String lyricsText) {
    final sourceLines = _numberedLines(scoreText);
    final headerCount =
        sourceLines.where((line) => _matchHeader(line.text) != null).length;
    final hasLyricsHeader = sourceLines.any(
      (line) => _matchHeader(line.text)?.section == _Section.lyrics,
    );
    final hasScoreHeader = sourceLines.any(
      (line) => _matchHeader(line.text)?.section == _Section.score,
    );
    return scoreText.contains(JianpuSyntax.sentenceSeparator) ||
        scoreText.contains(JianpuSyntax.rowSeparator) ||
        lyricsText.contains(JianpuSyntax.sentenceSeparator) ||
        lyricsText.contains(JianpuSyntax.rowSeparator) ||
        (hasLyricsHeader && !hasScoreHeader) ||
        headerCount > 2;
  }

  _DocumentSections _splitStructuredSections(
    String scoreText,
    String lyricsText,
  ) {
    final sourceLines = _numberedLines(scoreText);
    if (!_containsHeader(sourceLines)) {
      return _splitStructuredBareDocument(scoreText, lyricsText);
    }

    final scoreLines = <_SourceLine>[];
    final lyricLines = <_SourceLine>[];
    final errors = <ParseError>[];
    var section = _Section.none;
    var group = 0;
    _SegmentSplitter? scoreSplitter;
    _SegmentSplitter? lyricSplitter;

    void addLine(_Section target, _SourceLine line) {
      final splitter = target == _Section.score ? scoreSplitter : lyricSplitter;
      if (splitter == null) {
        errors.add(_structureError(line, '此处缺少 [谱] 标题。'));
        return;
      }
      final pieces = splitter.add(line, errors);
      if (target == _Section.score) {
        scoreLines.addAll(pieces);
      } else {
        lyricLines.addAll(pieces);
      }
    }

    for (final line in sourceLines) {
      final header = _matchHeader(line.text);
      if (header != null) {
        if (header.section == _Section.score) {
          group += 1;
          section = _Section.score;
          scoreSplitter = _SegmentSplitter(group);
          lyricSplitter = null;
        } else {
          if (group == 0 || section != _Section.score) {
            errors.add(_structureError(line, '[词] 前必须先有未配对的 [谱]。'));
            section = _Section.none;
            continue;
          }
          section = _Section.lyrics;
          lyricSplitter = _SegmentSplitter(group);
        }
        if (header.remainder.trim().isNotEmpty) {
          addLine(
            section,
            _SourceLine(
              number: line.number,
              text: header.remainder,
              columnOffset: line.text.length - header.remainder.length,
            ),
          );
        }
        continue;
      }
      if (line.text.trim().isEmpty) {
        continue;
      }
      addLine(section, line);
    }

    return _DocumentSections(
      scoreLines: scoreLines,
      lyricLines: lyricLines,
      errors: errors,
      inputWarnings: [
        if (lyricLines.isNotEmpty && lyricsText.trim().isNotEmpty)
          const ValidationMessage(
            line: 0,
            message: '已忽略独立歌词框：文档内已有 [词] 区块。',
          ),
      ],
    );
  }

  _DocumentSections _splitStructuredBareDocument(
    String scoreText,
    String lyricsText,
  ) {
    final errors = <ParseError>[];
    final scoreLines =
        _splitStructuredBody(_numberedLines(scoreText), 1, errors);
    final lyricLines =
        _splitStructuredBody(_numberedLines(lyricsText), 1, errors);
    return _DocumentSections(
      scoreLines: scoreLines,
      lyricLines: lyricLines,
      errors: errors,
    );
  }

  List<_SourceLine> _splitStructuredBody(
    List<_SourceLine> lines,
    int group,
    List<ParseError> errors,
  ) {
    final splitter = _SegmentSplitter(group);
    final result = <_SourceLine>[];
    for (final line in lines) {
      if (line.text.trim().isNotEmpty) {
        result.addAll(splitter.add(line, errors));
      }
    }
    return result;
  }

  ParseError _structureError(_SourceLine line, String message) => ParseError(
        line: line.number,
        column: line.columnOffset + 1,
        tokenIndex: 1,
        token: '',
        message: '第 ${line.number} 行第 ${line.columnOffset + 1} 列：$message',
      );

  _DocumentSections _extractHeaderedDocument(List<_SourceLine> lines) {
    final scoreLines = <_SourceLine>[];
    final lyricLines = <_SourceLine>[];
    _Section section = _Section.none;

    for (final line in lines) {
      final header = _matchHeader(line.text);
      if (header != null) {
        section = header.section;
        final remainder = header.remainder;
        if (remainder.trim().isNotEmpty) {
          final remainderLine = _SourceLine(
            number: line.number,
            text: remainder,
            columnOffset: line.text.length - remainder.length,
          );
          if (section == _Section.score) {
            scoreLines.add(remainderLine);
          } else if (section == _Section.lyrics) {
            lyricLines.add(remainderLine);
          }
        }
        continue;
      }

      if (line.text.trim().isEmpty) {
        continue;
      }

      if (section == _Section.score) {
        scoreLines.add(line);
      } else if (section == _Section.lyrics) {
        lyricLines.add(line);
      } else {
        scoreLines.add(line);
      }
    }

    return _DocumentSections(scoreLines: scoreLines, lyricLines: lyricLines);
  }

  List<_SourceLine> _numberedLines(String text) {
    if (text.isEmpty) {
      return const [];
    }
    final rawLines = text.split(RegExp(r'\r?\n'));
    final lines = <_SourceLine>[];
    for (var i = 0; i < rawLines.length; i++) {
      lines.add(_SourceLine(number: i + 1, text: rawLines[i]));
    }
    return lines;
  }

  List<_SourceLine> _contentLines(List<_SourceLine> lines) {
    final result = <_SourceLine>[];
    for (final line in lines) {
      if (line.text.trim().isEmpty) {
        continue;
      }
      final header = _matchHeader(line.text);
      if (header == null) {
        result.add(line);
        continue;
      }
      final remainder = header.remainder;
      if (remainder.trim().isNotEmpty) {
        result.add(
          _SourceLine(
            number: line.number,
            text: remainder,
            columnOffset: line.text.length - remainder.length,
          ),
        );
      }
    }
    return result;
  }

  bool _containsHeader(List<_SourceLine> lines) {
    return lines.any((line) => _matchHeader(line.text) != null);
  }

  _HeaderMatch? _matchHeader(String text) {
    final trimmed = text.trim();
    return _matchKnownHeader(
            trimmed, JianpuSyntax.scoreHeader, _Section.score) ??
        _matchKnownHeader(trimmed, JianpuSyntax.lyricsHeader, _Section.lyrics);
  }

  _HeaderMatch? _matchKnownHeader(
    String trimmed,
    String header,
    _Section section,
  ) {
    if (trimmed == header) {
      return _HeaderMatch(section: section, remainder: '');
    }
    if (trimmed.startsWith(header)) {
      final rest = trimmed.substring(header.length);
      if (rest.startsWith(' ') || rest.startsWith('\t')) {
        return _HeaderMatch(section: section, remainder: rest);
      }
    }
    return null;
  }
}

enum _Section { none, score, lyrics }

class _SourceLine {
  final int number;
  final String text;
  final int columnOffset;
  final InputSegment? segment;

  const _SourceLine({
    required this.number,
    required this.text,
    this.columnOffset = 0,
    this.segment,
  });
}

class _HeaderMatch {
  final _Section section;
  final String remainder;

  const _HeaderMatch({
    required this.section,
    required this.remainder,
  });
}

class _DocumentSections {
  final List<_SourceLine> scoreLines;
  final List<_SourceLine> lyricLines;
  final List<ParseError> errors;
  final List<ValidationMessage> inputWarnings;

  const _DocumentSections({
    required this.scoreLines,
    required this.lyricLines,
    this.errors = const [],
    this.inputWarnings = const [],
  });
}

class _SegmentSplitter {
  final int group;
  var _sentence = 1;
  var _row = 1;
  var _previousLineEnded = false;
  var _hasPreviousContent = false;

  _SegmentSplitter(this.group);

  List<_SourceLine> add(_SourceLine line, List<ParseError> errors) {
    if (_hasPreviousContent && !_previousLineEnded) {
      _row += 1;
    }
    _previousLineEnded = false;
    _hasPreviousContent = true;

    final results = <_SourceLine>[];
    var start = 0;
    var sawSeparator = false;
    for (var index = 0; index < line.text.length; index++) {
      final isSentence =
          line.text.startsWith(JianpuSyntax.sentenceSeparator, index);
      final isRow = line.text[index] == JianpuSyntax.rowSeparator;
      if (!isSentence && !isRow) {
        continue;
      }
      final separatorLength = isSentence ? 2 : 1;
      final part = line.text.substring(start, index);
      if (part.trim().isEmpty) {
        errors.add(_emptySegmentError(line, index));
      } else {
        results.add(_piece(line, part, start));
      }
      sawSeparator = true;
      if (isSentence) {
        _sentence += 1;
      } else {
        _row += 1;
      }
      start = index + separatorLength;
      if (isSentence) {
        index += 1;
      }
    }

    final remainder = line.text.substring(start);
    if (remainder.trim().isNotEmpty) {
      results.add(_piece(line, remainder, start));
    } else if (sawSeparator) {
      _previousLineEnded = true;
    }
    return results;
  }

  _SourceLine _piece(_SourceLine line, String text, int offset) => _SourceLine(
        number: line.number,
        text: text,
        columnOffset: line.columnOffset + offset,
        segment: InputSegment(group: group, sentence: _sentence, row: _row),
      );

  ParseError _emptySegmentError(_SourceLine line, int index) => ParseError(
        line: line.number,
        column: line.columnOffset + index + 1,
        tokenIndex: 1,
        token: index < line.text.length ? line.text[index] : '',
        message:
            '第 ${line.number} 行第 ${line.columnOffset + index + 1} 列：不允许空句或空行。',
      );
}
