import 'keyboard_mapping.dart';
import '../models/register.dart';

const _degreeCount = 7;

/// Editable key text for the three registers.
///
/// A group may be missing or contain values that are not yet valid keys.
/// [validate] is the only path that produces a [KeyboardMapping].
class MappingDraft {
  final List<String>? low;
  final List<String>? middle;
  final List<String>? high;

  const MappingDraft({
    this.low,
    this.middle,
    this.high,
  });

  /// Draft text copied from an existing mapping.
  factory MappingDraft.fromMapping(KeyboardMapping mapping) {
    return MappingDraft(
      low: mapping.low,
      middle: mapping.middle,
      high: mapping.high,
    );
  }

  /// Checks every group and returns a mapping only when all 21 keys are legal.
  MappingDraftValidation validate() {
    final errors = <MappingDraftError>[];
    final normalized = <Register, List<String>>{};

    _collectGroup(Register.low, low, errors, normalized);
    _collectGroup(Register.middle, middle, errors, normalized);
    _collectGroup(Register.high, high, errors, normalized);

    final warnings = _duplicateWarnings(normalized);
    if (errors.isNotEmpty) {
      return MappingDraftValidation(
        errors: List.unmodifiable(errors),
        warnings: List.unmodifiable(warnings),
      );
    }

    return MappingDraftValidation(
      errors: const [],
      warnings: List.unmodifiable(warnings),
      mapping: KeyboardMapping.fromLists(
        low: normalized[Register.low]!,
        middle: normalized[Register.middle]!,
        high: normalized[Register.high]!,
      ),
    );
  }
}

/// Structured outcome of checking a [MappingDraft].
///
/// Duplicate keys are warnings. Any illegal or missing key leaves [mapping]
/// null so conversion cannot use the draft.
class MappingDraftValidation {
  final List<MappingDraftError> errors;
  final List<MappingDraftWarning> warnings;
  final KeyboardMapping? mapping;

  const MappingDraftValidation({
    required this.errors,
    required this.warnings,
    this.mapping,
  });

  bool get isValid => errors.isEmpty && mapping != null;
}

/// One blocking problem in a mapping draft.
class MappingDraftError {
  final Register register;
  final int? degree;
  final String value;
  final String message;

  const MappingDraftError({
    required this.register,
    required this.degree,
    required this.value,
    required this.message,
  });
}

/// A non-blocking mapping finding. Duplicate keys still produce a mapping.
class MappingDraftWarning {
  final String key;
  final String message;

  const MappingDraftWarning({
    required this.key,
    required this.message,
  });
}

void _collectGroup(
  Register register,
  List<String>? keys,
  List<MappingDraftError> errors,
  Map<Register, List<String>> normalized,
) {
  final label = _registerLabel(register);
  if (keys == null) {
    errors.add(
      MappingDraftError(
        register: register,
        degree: null,
        value: '',
        message: '缺少$label键位。',
      ),
    );
    return;
  }
  if (keys.length != _degreeCount) {
    errors.add(
      MappingDraftError(
        register: register,
        degree: null,
        value: '',
        message: '$label需要 $_degreeCount 个键位，当前有 ${keys.length} 个。',
      ),
    );
    return;
  }

  final letters = <String>[];
  for (var index = 0; index < keys.length; index++) {
    final value = keys[index];
    if (!_isAsciiLetter(value)) {
      final degree = index + 1;
      errors.add(
        MappingDraftError(
          register: register,
          degree: degree,
          value: value,
          message: '$label $degree 必须是一个英文字母。',
        ),
      );
      continue;
    }
    letters.add(value.toUpperCase());
  }
  if (letters.length == _degreeCount) {
    normalized[register] = letters;
  }
}

List<MappingDraftWarning> _duplicateWarnings(
  Map<Register, List<String>> normalized,
) {
  final counts = <String, int>{};
  for (final register in Register.values) {
    final letters = normalized[register];
    if (letters == null) {
      continue;
    }
    for (final letter in letters) {
      counts[letter] = (counts[letter] ?? 0) + 1;
    }
  }

  return [
    for (final entry in counts.entries)
      if (entry.value > 1)
        MappingDraftWarning(
          key: entry.key,
          message: '键 ${entry.key} 被多个音符使用',
        ),
  ];
}

bool _isAsciiLetter(String value) {
  if (value.length != 1) {
    return false;
  }
  final code = value.codeUnitAt(0);
  final isUpper = code >= 0x41 && code <= 0x5A;
  final isLower = code >= 0x61 && code <= 0x7A;
  return isUpper || isLower;
}

String _registerLabel(Register register) {
  return switch (register) {
    Register.low => '低音',
    Register.middle => '中音',
    Register.high => '高音',
  };
}
