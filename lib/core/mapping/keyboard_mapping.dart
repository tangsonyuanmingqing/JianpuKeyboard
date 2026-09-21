import '../models/music_token.dart';
import '../models/register.dart';
import '../models/score.dart';

/// Central keyboard mapping from Jianpu degree + register to a key letter.
class KeyboardMapping {
  static const _lowKeys = ['Z', 'X', 'C', 'V', 'B', 'N', 'M'];
  static const _middleKeys = ['A', 'S', 'D', 'F', 'G', 'H', 'J'];
  static const _highKeys = ['Q', 'W', 'E', 'R', 'T', 'Y', 'U'];

  const KeyboardMapping();

  /// Returns the keyboard letter for [degree] (1-7) in [register].
  String keyFor(int degree, Register register) {
    final keys = switch (register) {
      Register.low => _lowKeys,
      Register.middle => _middleKeys,
      Register.high => _highKeys,
    };
    return keys[degree - 1];
  }

  /// Returns a new [Score] with [Note.keyboardKey] filled in.
  Score apply(Score score) {
    return Score(
      lines: [
        for (final line in score.lines)
          ScoreLine(
            lineNumber: line.lineNumber,
            tokens: [
              for (final token in line.tokens)
                if (token is Note)
                  token.copyWith(
                    keyboardKey: keyFor(token.degree, token.register),
                  )
                else
                  token,
            ],
          ),
      ],
    );
  }
}
