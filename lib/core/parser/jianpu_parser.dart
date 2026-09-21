import '../models/lyric_line.dart';
import '../models/music_token.dart';
import '../models/parse_error.dart';
import '../models/parse_result.dart';
import '../models/register.dart';
import '../models/score.dart';
import '../models/source_position.dart';
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
    final sections = _splitSections(scoreText, lyricsText);
    final errors = <ParseError>[];
    final scoreLines = <ScoreLine>[];

    for (final line in sections.scoreLines) {
      final tokens = <MusicToken>[];
      for (final raw in _tokenizer.tokenizeLine(line.text, line.number)) {
        final token = _classifyScoreToken(raw, errors);
        if (token != null) {
          tokens.add(token);
        }
      }
      if (tokens.isNotEmpty) {
        scoreLines.add(ScoreLine(lineNumber: line.number, tokens: tokens));
      }
    }

    if (errors.isNotEmpty) {
      return ParseFailure(errors);
    }

    final lyricLines = <LyricLine>[];
    for (final line in sections.lyricLines) {
      final lyricLine = _lyricTokenizer.tokenizeLine(line.text, line.number);
      if (lyricLine.tokens.isNotEmpty) {
        lyricLines.add(lyricLine);
      }
    }

    return ParseSuccess(
      score: Score(lines: scoreLines),
      lyricLines: lyricLines,
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
      return extracted;
    }

    return _DocumentSections(
      scoreLines: _contentLines(scoreSourceLines),
      lyricLines: _contentLines(_numberedLines(lyricsText)),
    );
  }

  _DocumentSections _extractHeaderedDocument(List<_SourceLine> lines) {
    final scoreLines = <_SourceLine>[];
    final lyricLines = <_SourceLine>[];
    _Section section = _Section.none;

    for (final line in lines) {
      final header = _matchHeader(line.text);
      if (header != null) {
        section = header.section;
        final remainder = header.remainder.trim();
        if (remainder.isNotEmpty) {
          final remainderLine =
              _SourceLine(number: line.number, text: remainder);
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
      final remainder = header.remainder.trim();
      if (remainder.isNotEmpty) {
        result.add(_SourceLine(number: line.number, text: remainder));
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

  const _SourceLine({required this.number, required this.text});
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

  const _DocumentSections({
    required this.scoreLines,
    required this.lyricLines,
  });
}
