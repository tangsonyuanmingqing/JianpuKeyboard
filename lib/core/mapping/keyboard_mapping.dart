import '../models/music_token.dart';
import '../models/register.dart';
import '../models/score.dart';
import 'keyboard_mapping_json.dart';

/// Immutable mapping from Jianpu degree + register to a single key letter.
///
/// [low], [middle] and [high] each hold seven letters.
/// Index 0 is degree 1 and index 6 is degree 7.
/// [KeyboardMapping.new] is the built-in default mapping.
///
/// The default lists are compile-time constants. [KeyboardMapping.fromLists]
/// copies its arguments, so later edits to those lists do not change the
/// mapping. Exposed lists reject element assignment.
class KeyboardMapping {
  static const jsonVersion = 1;

  static const _defaultLow = ['Z', 'X', 'C', 'V', 'B', 'N', 'M'];
  static const _defaultMiddle = ['A', 'S', 'D', 'F', 'G', 'H', 'J'];
  static const _defaultHigh = ['Q', 'W', 'E', 'R', 'T', 'Y', 'U'];

  final List<String> low;
  final List<String> middle;
  final List<String> high;

  const KeyboardMapping()
      : this._(
          low: _defaultLow,
          middle: _defaultMiddle,
          high: _defaultHigh,
        );

  const KeyboardMapping._({
    required this.low,
    required this.middle,
    required this.high,
  });

  /// Copies [low], [middle] and [high] into lists that cannot be modified.
  factory KeyboardMapping.fromLists({
    required List<String> low,
    required List<String> middle,
    required List<String> high,
  }) {
    return KeyboardMapping._(
      low: _frozenCopy(low),
      middle: _frozenCopy(middle),
      high: _frozenCopy(high),
    );
  }

  static List<String> _frozenCopy(List<String> keys) {
    return List<String>.unmodifiable(List<String>.of(keys));
  }

  /// Serializes this mapping as a version 1 JSON object.
  ///
  /// The returned lists are copies of the stored letters.
  Map<String, Object?> toJson() {
    return {
      'version': jsonVersion,
      'low': List<String>.of(low),
      'middle': List<String>.of(middle),
      'high': List<String>.of(high),
    };
  }

  /// Decodes a version 1 mapping document.
  ///
  /// Structural problems and illegal keys leave [KeyboardMappingJsonResult.mapping]
  /// null. Duplicate keys stay valid and are returned as warnings.
  static KeyboardMappingJsonResult fromJson(Object? json) {
    return decodeKeyboardMapping(json);
  }

  /// Returns the keyboard letter for [degree] (1-7) in [register].
  String keyFor(int degree, Register register) {
    final keys = switch (register) {
      Register.low => low,
      Register.middle => middle,
      Register.high => high,
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
