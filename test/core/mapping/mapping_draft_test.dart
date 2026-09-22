import 'package:flutter_test/flutter_test.dart';
import 'package:jianpu_keyboard/core/mapping/keyboard_mapping.dart';
import 'package:jianpu_keyboard/core/mapping/mapping_draft.dart';
import 'package:jianpu_keyboard/core/models/register.dart';

void main() {
  const defaults = KeyboardMapping();

  MappingDraft draft({
    List<String>? low,
    List<String>? middle,
    List<String>? high,
  }) {
    return MappingDraft(
      low: low ?? defaults.low,
      middle: middle ?? defaults.middle,
      high: high ?? defaults.high,
    );
  }

  List<String> replaceKey(List<String> keys, int degree, String value) {
    return [
      for (var index = 0; index < keys.length; index++)
        if (index == degree - 1) value else keys[index],
    ];
  }

  test('accepts the default mapping and builds a KeyboardMapping', () {
    final result = MappingDraft.fromMapping(defaults).validate();

    expect(result.isValid, isTrue);
    expect(result.errors, isEmpty);
    expect(result.warnings, isEmpty);
    expect(result.mapping, isNotNull);
    expect(result.mapping!.low, defaults.low);
    expect(result.mapping!.middle, defaults.middle);
    expect(result.mapping!.high, defaults.high);
    expect(result.mapping!.keyFor(3, Register.middle), 'D');
  });

  test('builds a KeyboardMapping from a valid custom draft', () {
    final result = draft(
      low: ['A', 'B', 'C', 'D', 'E', 'F', 'G'],
      middle: ['H', 'I', 'J', 'K', 'L', 'M', 'N'],
      high: ['O', 'P', 'Q', 'R', 'S', 'T', 'U'],
    ).validate();

    expect(result.isValid, isTrue);
    expect(result.warnings, isEmpty);
    expect(result.mapping!.keyFor(1, Register.low), 'A');
    expect(result.mapping!.keyFor(7, Register.low), 'G');
    expect(result.mapping!.keyFor(1, Register.middle), 'H');
    expect(result.mapping!.keyFor(7, Register.middle), 'N');
    expect(result.mapping!.keyFor(1, Register.high), 'O');
    expect(result.mapping!.keyFor(7, Register.high), 'U');
  });

  test('normalizes lowercase letters to uppercase', () {
    final sourceLow = ['a', 'b', 'c', 'd', 'e', 'f', 'g'];
    final result = draft(
      low: sourceLow,
      middle: ['h', 'i', 'j', 'k', 'l', 'm', 'n'],
      high: ['o', 'p', 'q', 'r', 's', 't', 'u'],
    ).validate();

    expect(result.isValid, isTrue);
    expect(result.warnings, isEmpty);
    expect(result.mapping!.keyFor(1, Register.low), 'A');
    expect(result.mapping!.keyFor(3, Register.middle), 'J');
    expect(result.mapping!.keyFor(7, Register.high), 'U');
    sourceLow[0] = 'z';
    expect(result.mapping!.keyFor(1, Register.low), 'A');
    expect(() => result.mapping!.low[0] = 'Z', throwsUnsupportedError);
    expect(result.mapping!.keyFor(1, Register.low), 'A');
  });

  test('validated mapping stays unchanged when the source list changes', () {
    final low = ['A', 'B', 'C', 'D', 'E', 'F', 'G'];
    final result = draft(
      low: low,
      middle: ['H', 'I', 'J', 'K', 'L', 'M', 'N'],
      high: ['O', 'P', 'Q', 'R', 'S', 'T', 'U'],
    ).validate();

    low[0] = 'Z';

    expect(result.mapping!.low, ['A', 'B', 'C', 'D', 'E', 'F', 'G']);
    expect(result.mapping!.keyFor(1, Register.low), 'A');
    expect(() => result.mapping!.low[0] = 'Z', throwsUnsupportedError);
    expect(result.mapping!.keyFor(1, Register.low), 'A');
  });

  test('rejects an empty key', () {
    final result = draft(
      middle: replaceKey(defaults.middle, 4, ''),
    ).validate();

    expect(result.isValid, isFalse);
    expect(result.mapping, isNull);
    final error = result.errors.single;
    expect(error.register, Register.middle);
    expect(error.degree, 4);
    expect(error.value, '');
    expect(error.message, '中音 4 必须是一个英文字母。');
  });

  test('rejects a space', () {
    final result = draft(
      low: replaceKey(defaults.low, 2, ' '),
    ).validate();

    expect(result.isValid, isFalse);
    expect(result.mapping, isNull);
    expect(result.errors.single.degree, 2);
    expect(result.errors.single.value, ' ');
    expect(result.errors.single.message, '低音 2 必须是一个英文字母。');
  });

  test('rejects a digit', () {
    final result = draft(
      high: replaceKey(defaults.high, 1, '1'),
    ).validate();

    expect(result.isValid, isFalse);
    expect(result.mapping, isNull);
    expect(result.errors.single.register, Register.high);
    expect(result.errors.single.degree, 1);
    expect(result.errors.single.value, '1');
  });

  test('rejects a symbol', () {
    final result = draft(
      middle: replaceKey(defaults.middle, 3, '-'),
    ).validate();

    expect(result.isValid, isFalse);
    expect(result.mapping, isNull);
    expect(result.errors.single.degree, 3);
    expect(result.errors.single.value, '-');
  });

  test('rejects multiple characters', () {
    final result = draft(
      low: replaceKey(defaults.low, 5, 'AB'),
    ).validate();

    expect(result.isValid, isFalse);
    expect(result.mapping, isNull);
    expect(result.errors.single.degree, 5);
    expect(result.errors.single.value, 'AB');
  });

  test('rejects a missing low group', () {
    final result = MappingDraft(
      middle: defaults.middle,
      high: defaults.high,
    ).validate();

    expect(result.isValid, isFalse);
    expect(result.mapping, isNull);
    final error = result.errors.single;
    expect(error.register, Register.low);
    expect(error.degree, isNull);
    expect(error.message, '缺少低音键位。');
  });

  test('rejects a missing middle group', () {
    final result = MappingDraft(
      low: defaults.low,
      high: defaults.high,
    ).validate();

    expect(result.isValid, isFalse);
    expect(result.mapping, isNull);
    expect(result.errors.single.register, Register.middle);
    expect(result.errors.single.message, '缺少中音键位。');
  });

  test('rejects a missing high group', () {
    final result = MappingDraft(
      low: defaults.low,
      middle: defaults.middle,
    ).validate();

    expect(result.isValid, isFalse);
    expect(result.mapping, isNull);
    expect(result.errors.single.register, Register.high);
    expect(result.errors.single.message, '缺少高音键位。');
  });

  test('rejects a register group with fewer than 7 keys', () {
    final result = draft(
      high: ['Q', 'W', 'E', 'R', 'T', 'Y'],
    ).validate();

    expect(result.isValid, isFalse);
    expect(result.mapping, isNull);
    final error = result.errors.single;
    expect(error.register, Register.high);
    expect(error.degree, isNull);
    expect(error.message, '高音需要 7 个键位，当前有 6 个。');
  });

  test('rejects a register group with more than 7 keys', () {
    final result = draft(
      low: ['Z', 'X', 'C', 'V', 'B', 'N', 'M', 'A'],
    ).validate();

    expect(result.isValid, isFalse);
    expect(result.mapping, isNull);
    expect(result.errors.single.register, Register.low);
    expect(result.errors.single.degree, isNull);
    expect(result.errors.single.message, '低音需要 7 个键位，当前有 8 个。');
  });

  test('allows duplicate keys and reports one warning', () {
    final result = draft(
      middle: replaceKey(defaults.middle, 2, 'A'),
    ).validate();

    expect(result.isValid, isTrue);
    expect(result.errors, isEmpty);
    expect(result.mapping, isNotNull);
    expect(result.mapping!.keyFor(1, Register.middle), 'A');
    expect(result.mapping!.keyFor(2, Register.middle), 'A');
    expect(result.warnings, hasLength(1));
    expect(result.warnings.single.key, 'A');
    expect(result.warnings.single.message, '键 A 被多个音符使用');
  });

  test('reports one warning when the same key is used more than twice', () {
    final result = draft(
      low: replaceKey(defaults.low, 1, 'A'),
      high: replaceKey(defaults.high, 1, 'a'),
    ).validate();

    expect(result.isValid, isTrue);
    expect(result.mapping!.keyFor(1, Register.low), 'A');
    expect(result.mapping!.keyFor(1, Register.high), 'A');
    expect(result.warnings, hasLength(1));
    expect(result.warnings.single.message, '键 A 被多个音符使用');
  });
}
