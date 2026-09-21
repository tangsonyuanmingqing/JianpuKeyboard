import 'register.dart';
import 'source_position.dart';

/// A structural token in a parsed score line.
sealed class MusicToken {
  final SourcePosition position;

  const MusicToken({required this.position});
}

/// A pitched note with optional lyric and mapped keyboard key.
class Note extends MusicToken {
  final int degree;
  final Register register;
  final String? lyric;
  final String? keyboardKey;

  const Note({
    required super.position,
    required this.degree,
    required this.register,
    this.lyric,
    this.keyboardKey,
  });

  Note copyWith({
    String? lyric,
    String? keyboardKey,
  }) {
    return Note(
      position: position,
      degree: degree,
      register: register,
      lyric: lyric ?? this.lyric,
      keyboardKey: keyboardKey ?? this.keyboardKey,
    );
  }
}

/// A rest that is preserved in output and does not consume lyrics.
class Rest extends MusicToken {
  const Rest({required super.position});
}

/// A hold that continues the previous note and does not consume lyrics.
class Hold extends MusicToken {
  const Hold({required super.position});
}

/// A measure bar that is preserved in output.
class MeasureBar extends MusicToken {
  const MeasureBar({required super.position});
}
