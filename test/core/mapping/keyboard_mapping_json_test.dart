import 'package:flutter_test/flutter_test.dart';
import 'package:jianpu_keyboard/core/mapping/keyboard_mapping.dart';
import 'package:jianpu_keyboard/core/mapping/keyboard_mapping_json.dart';
import 'package:jianpu_keyboard/core/models/register.dart';

void main() {
  const defaults = KeyboardMapping();

  Map<String, Object?> document({
    Object? version = 1,
    bool includeVersion = true,
    Object? low,
    bool includeLow = true,
    Object? middle,
    bool includeMiddle = true,
    Object? high,
    bool includeHigh = true,
    Map<String, Object?> extra = const {},
  }) {
    return {
      if (includeVersion) 'version': version,
      if (includeLow) 'low': low ?? defaults.low,
      if (includeMiddle) 'middle': middle ?? defaults.middle,
      if (includeHigh) 'high': high ?? defaults.high,
      ...extra,
    };
  }

  List<String> replaceKey(List<String> keys, int degree, String value) {
    return [
      for (var index = 0; index < keys.length; index++)
        if (index == degree - 1) value else keys[index],
    ];
  }

  void expectFailure(
    Object? json,
    KeyboardMappingJsonIssue issue, {
    String? field,
  }) {
    final result = KeyboardMapping.fromJson(json);
    expect(result.isValid, isFalse);
    expect(result.mapping, isNull);
    expect(result.errors, isNotEmpty);
    expect(result.errors.first.issue, issue);
    if (field != null) {
      expect(result.errors.first.field, field);
    }
  }

  test('round-trips the default mapping', () {
    final json = defaults.toJson();

    expect(json['version'], 1);
    expect(json['low'], ['Z', 'X', 'C', 'V', 'B', 'N', 'M']);
    expect(json['middle'], ['A', 'S', 'D', 'F', 'G', 'H', 'J']);
    expect(json['high'], ['Q', 'W', 'E', 'R', 'T', 'Y', 'U']);
    expect(json.length, 4);

    final result = KeyboardMapping.fromJson(json);
    expect(result.isValid, isTrue);
    expect(result.warnings, isEmpty);
    expect(result.mapping!.low, defaults.low);
    expect(result.mapping!.middle, defaults.middle);
    expect(result.mapping!.high, defaults.high);
    expect(result.mapping!.keyFor(3, Register.middle), 'D');
  });

  test('round-trips a custom mapping', () {
    final mapping = KeyboardMapping.fromLists(
      low: ['A', 'B', 'C', 'D', 'E', 'F', 'G'],
      middle: ['H', 'I', 'J', 'K', 'L', 'M', 'N'],
      high: ['O', 'P', 'Q', 'R', 'S', 'T', 'U'],
    );

    final result = KeyboardMapping.fromJson(mapping.toJson());

    expect(result.isValid, isTrue);
    expect(result.warnings, isEmpty);
    expect(result.mapping!.low, mapping.low);
    expect(result.mapping!.middle, mapping.middle);
    expect(result.mapping!.high, mapping.high);
    expect(result.mapping!.keyFor(1, Register.low), 'A');
    expect(result.mapping!.keyFor(7, Register.middle), 'N');
    expect(result.mapping!.keyFor(7, Register.high), 'U');
  });

  test('rejects a document without version', () {
    expectFailure(
      document(includeVersion: false),
      KeyboardMappingJsonIssue.missingField,
      field: 'version',
    );
  });

  test('rejects a version that is not an int', () {
    expectFailure(
      document(version: '1'),
      KeyboardMappingJsonIssue.invalidType,
      field: 'version',
    );
  });

  test('rejects version 2', () {
    expectFailure(
      document(version: 2),
      KeyboardMappingJsonIssue.unsupportedVersion,
      field: 'version',
    );
  });

  test('rejects version 0', () {
    expectFailure(
      document(version: 0),
      KeyboardMappingJsonIssue.unsupportedVersion,
      field: 'version',
    );
  });

  test('rejects a document without low', () {
    expectFailure(
      document(includeLow: false),
      KeyboardMappingJsonIssue.missingField,
      field: 'low',
    );
  });

  test('rejects a document without middle', () {
    expectFailure(
      document(includeMiddle: false),
      KeyboardMappingJsonIssue.missingField,
      field: 'middle',
    );
  });

  test('rejects a document without high', () {
    expectFailure(
      document(includeHigh: false),
      KeyboardMappingJsonIssue.missingField,
      field: 'high',
    );
  });

  test('rejects a low value that is not a list', () {
    expectFailure(
      document(low: 'ZXCVBNM'),
      KeyboardMappingJsonIssue.invalidType,
      field: 'low',
    );
  });

  test('rejects a middle value that is not a list', () {
    expectFailure(
      document(middle: 1),
      KeyboardMappingJsonIssue.invalidType,
      field: 'middle',
    );
  });

  test('rejects a high value that is not a list', () {
    expectFailure(
      document(high: true),
      KeyboardMappingJsonIssue.invalidType,
      field: 'high',
    );
  });

  test('rejects a low group with 6 keys', () {
    expectFailure(
      document(low: ['Z', 'X', 'C', 'V', 'B', 'N']),
      KeyboardMappingJsonIssue.invalidLength,
      field: 'low',
    );
  });

  test('rejects a middle group with 8 keys', () {
    expectFailure(
      document(
        middle: ['A', 'S', 'D', 'F', 'G', 'H', 'J', 'K'],
      ),
      KeyboardMappingJsonIssue.invalidLength,
      field: 'middle',
    );
  });

  test('rejects a high group with the wrong length', () {
    expectFailure(
      document(high: ['Q', 'W', 'E', 'R', 'T']),
      KeyboardMappingJsonIssue.invalidLength,
      field: 'high',
    );
  });

  test('rejects an empty key', () {
    expectFailure(
      document(low: replaceKey(defaults.low, 1, '')),
      KeyboardMappingJsonIssue.invalidKey,
      field: 'low',
    );
  });

  test('rejects a space', () {
    expectFailure(
      document(middle: replaceKey(defaults.middle, 2, ' ')),
      KeyboardMappingJsonIssue.invalidKey,
      field: 'middle',
    );
  });

  test('rejects a digit', () {
    expectFailure(
      document(high: replaceKey(defaults.high, 3, '1')),
      KeyboardMappingJsonIssue.invalidKey,
      field: 'high',
    );
  });

  test('rejects a symbol', () {
    expectFailure(
      document(low: replaceKey(defaults.low, 4, '-')),
      KeyboardMappingJsonIssue.invalidKey,
      field: 'low',
    );
  });

  test('rejects multiple characters without truncating them', () {
    final result = KeyboardMapping.fromJson(
      document(middle: replaceKey(defaults.middle, 3, 'AB')),
    );

    expect(result.mapping, isNull);
    expect(result.errors.single.issue, KeyboardMappingJsonIssue.invalidKey);
    expect(result.errors.single.message, contains('必须是一个英文字母'));
  });

  test('rejects a null key', () {
    final low = ['Z', null, 'C', 'V', 'B', 'N', 'M'];
    expectFailure(
      document(low: low),
      KeyboardMappingJsonIssue.invalidKey,
      field: 'low',
    );
  });

  test('normalizes lowercase letters to uppercase', () {
    final low = ['a', 'b', 'c', 'd', 'e', 'f', 'g'];
    final result = KeyboardMapping.fromJson(
      document(
        low: low,
        middle: ['h', 'i', 'j', 'k', 'l', 'm', 'n'],
        high: ['o', 'p', 'q', 'r', 's', 't', 'u'],
      ),
    );

    expect(result.isValid, isTrue);
    expect(result.warnings, isEmpty);
    expect(result.mapping!.keyFor(1, Register.low), 'A');
    expect(result.mapping!.keyFor(7, Register.middle), 'N');
    expect(result.mapping!.keyFor(1, Register.high), 'O');
    low[0] = 'Z';
    expect(result.mapping!.keyFor(1, Register.low), 'A');
  });

  test('ignores unknown fields', () {
    final result = KeyboardMapping.fromJson(
      document(extra: const {'futureField': true}),
    );

    expect(result.isValid, isTrue);
    expect(result.mapping!.low, defaults.low);
    expect(result.mapping!.middle, defaults.middle);
    expect(result.mapping!.high, defaults.high);
  });

  test('accepts duplicate keys and keeps the warning', () {
    final result = KeyboardMapping.fromJson(
      document(
        low: ['A', 'A', 'C', 'D', 'E', 'F', 'G'],
        middle: ['H', 'I', 'J', 'K', 'L', 'M', 'N'],
        high: ['O', 'P', 'Q', 'R', 'S', 'T', 'U'],
      ),
    );

    expect(result.isValid, isTrue);
    expect(result.mapping, isNotNull);
    expect(result.mapping!.keyFor(1, Register.low), 'A');
    expect(result.mapping!.keyFor(2, Register.low), 'A');
    expect(result.warnings.single.key, 'A');
    expect(result.warnings.single.message, '键 A 被多个音符使用');
  });

  test('returns an immutable mapping', () {
    final low = ['Z', 'X', 'C', 'V', 'B', 'N', 'M'];
    final result = KeyboardMapping.fromJson(document(low: low));
    final mapping = result.mapping!;

    low[0] = 'A';
    expect(mapping.keyFor(1, Register.low), 'Z');
    expect(() => mapping.low[0] = 'A', throwsUnsupportedError);
    expect(() => mapping.middle[0] = 'Z', throwsUnsupportedError);
    expect(() => mapping.high[0] = 'Z', throwsUnsupportedError);
    expect(mapping.low, defaults.low);
  });
}
