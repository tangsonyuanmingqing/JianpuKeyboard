import 'package:flutter_test/flutter_test.dart';
import 'package:jianpu_keyboard/core/mapping/keyboard_mapping.dart';
import 'package:jianpu_keyboard/core/models/register.dart';

void main() {
  const mapping = KeyboardMapping();

  group('middle register', () {
    test('converts middle-register 1 to A', () {
      expect(mapping.keyFor(1, Register.middle), 'A');
    });
    test('converts middle-register 2 to S', () {
      expect(mapping.keyFor(2, Register.middle), 'S');
    });
    test('converts middle-register 3 to D', () {
      expect(mapping.keyFor(3, Register.middle), 'D');
    });
    test('converts middle-register 4 to F', () {
      expect(mapping.keyFor(4, Register.middle), 'F');
    });
    test('converts middle-register 5 to G', () {
      expect(mapping.keyFor(5, Register.middle), 'G');
    });
    test('converts middle-register 6 to H', () {
      expect(mapping.keyFor(6, Register.middle), 'H');
    });
    test('converts middle-register 7 to J', () {
      expect(mapping.keyFor(7, Register.middle), 'J');
    });
  });

  group('high register', () {
    test('converts high-register 1 to Q', () {
      expect(mapping.keyFor(1, Register.high), 'Q');
    });
    test('converts high-register 2 to W', () {
      expect(mapping.keyFor(2, Register.high), 'W');
    });
    test('converts high-register 3 to E', () {
      expect(mapping.keyFor(3, Register.high), 'E');
    });
    test('converts high-register 4 to R', () {
      expect(mapping.keyFor(4, Register.high), 'R');
    });
    test('converts high-register 5 to T', () {
      expect(mapping.keyFor(5, Register.high), 'T');
    });
    test('converts high-register 6 to Y', () {
      expect(mapping.keyFor(6, Register.high), 'Y');
    });
    test('converts high-register 7 to U', () {
      expect(mapping.keyFor(7, Register.high), 'U');
    });
  });

  group('low register', () {
    test('converts low-register 1 to Z', () {
      expect(mapping.keyFor(1, Register.low), 'Z');
    });
    test('converts low-register 2 to X', () {
      expect(mapping.keyFor(2, Register.low), 'X');
    });
    test('converts low-register 3 to C', () {
      expect(mapping.keyFor(3, Register.low), 'C');
    });
    test('converts low-register 4 to V', () {
      expect(mapping.keyFor(4, Register.low), 'V');
    });
    test('converts low-register 5 to B', () {
      expect(mapping.keyFor(5, Register.low), 'B');
    });
    test('converts low-register 6 to N', () {
      expect(mapping.keyFor(6, Register.low), 'N');
    });
    test('converts low-register 7 to M', () {
      expect(mapping.keyFor(7, Register.low), 'M');
    });
  });

  test('stores the default 21 keys on the mapping', () {
    expect(mapping.low, ['Z', 'X', 'C', 'V', 'B', 'N', 'M']);
    expect(mapping.middle, ['A', 'S', 'D', 'F', 'G', 'H', 'J']);
    expect(mapping.high, ['Q', 'W', 'E', 'R', 'T', 'Y', 'U']);
  });

  test('reads letters from a custom 3 by 7 mapping', () {
    final custom = KeyboardMapping.fromLists(
      low: ['A', 'B', 'C', 'D', 'E', 'F', 'G'],
      middle: ['H', 'I', 'J', 'K', 'L', 'M', 'N'],
      high: ['O', 'P', 'Q', 'R', 'S', 'T', 'U'],
    );

    expect(custom.keyFor(1, Register.low), 'A');
    expect(custom.keyFor(7, Register.low), 'G');
    expect(custom.keyFor(1, Register.middle), 'H');
    expect(custom.keyFor(7, Register.middle), 'N');
    expect(custom.keyFor(1, Register.high), 'O');
    expect(custom.keyFor(7, Register.high), 'U');
  });

  test('keeps its letters when the source lists are later changed', () {
    final low = ['A', 'B', 'C', 'D', 'E', 'F', 'G'];
    final middle = ['H', 'I', 'J', 'K', 'L', 'M', 'N'];
    final high = ['O', 'P', 'Q', 'R', 'S', 'T', 'U'];
    final custom = KeyboardMapping.fromLists(
      low: low,
      middle: middle,
      high: high,
    );

    low[0] = 'Z';
    middle[0] = 'Z';
    high[0] = 'Z';

    expect(custom.low, ['A', 'B', 'C', 'D', 'E', 'F', 'G']);
    expect(custom.middle, ['H', 'I', 'J', 'K', 'L', 'M', 'N']);
    expect(custom.high, ['O', 'P', 'Q', 'R', 'S', 'T', 'U']);
    expect(custom.keyFor(1, Register.low), 'A');
    expect(custom.keyFor(1, Register.middle), 'H');
    expect(custom.keyFor(1, Register.high), 'O');
  });

  test('rejects assignment through the default key lists', () {
    expect(() => mapping.low[0] = 'A', throwsUnsupportedError);
    expect(() => mapping.middle[0] = 'Z', throwsUnsupportedError);
    expect(() => mapping.high[0] = 'Z', throwsUnsupportedError);
    expect(mapping.keyFor(1, Register.low), 'Z');
    expect(mapping.keyFor(1, Register.middle), 'A');
    expect(mapping.keyFor(1, Register.high), 'Q');
  });

  test('rejects assignment through a custom mapping key list', () {
    final custom = KeyboardMapping.fromLists(
      low: ['A', 'B', 'C', 'D', 'E', 'F', 'G'],
      middle: ['H', 'I', 'J', 'K', 'L', 'M', 'N'],
      high: ['O', 'P', 'Q', 'R', 'S', 'T', 'U'],
    );

    expect(() => custom.low[0] = 'Z', throwsUnsupportedError);
    expect(() => custom.middle[0] = 'Z', throwsUnsupportedError);
    expect(() => custom.high[0] = 'Z', throwsUnsupportedError);
    expect(custom.keyFor(1, Register.low), 'A');
    expect(custom.keyFor(1, Register.middle), 'H');
    expect(custom.keyFor(1, Register.high), 'O');
  });
}
