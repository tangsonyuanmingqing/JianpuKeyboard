import '../models/register.dart';
import 'keyboard_mapping.dart';
import 'mapping_draft.dart';

/// Why a mapping JSON document was rejected.
enum KeyboardMappingJsonIssue {
  unsupportedVersion,
  missingField,
  invalidType,
  invalidLength,
  invalidKey,
}

/// One structural or key problem in a mapping JSON document.
class KeyboardMappingJsonError {
  final KeyboardMappingJsonIssue issue;
  final String field;
  final String message;

  const KeyboardMappingJsonError({
    required this.issue,
    required this.field,
    required this.message,
  });
}

/// Outcome of [KeyboardMapping.fromJson].
///
/// A damaged document does not produce a [KeyboardMapping]. Duplicate keys
/// are warnings on a successful decode.
class KeyboardMappingJsonResult {
  final KeyboardMapping? mapping;
  final List<KeyboardMappingJsonError> errors;
  final List<MappingDraftWarning> warnings;

  const KeyboardMappingJsonResult({
    required this.mapping,
    required this.errors,
    required this.warnings,
  });

  bool get isValid => errors.isEmpty && mapping != null;
}

/// Reads a version 1 mapping document.
///
/// Version, field presence and JSON types are checked here. Letter shape,
/// group length, case and duplicate keys go through [MappingDraft.validate].
KeyboardMappingJsonResult decodeKeyboardMapping(Object? json) {
  final document = _stringKeyMap(json);
  if (document == null) {
    return _failure(const [
      KeyboardMappingJsonError(
        issue: KeyboardMappingJsonIssue.invalidType,
        field: 'json',
        message: '键盘映射 JSON 必须是对象。',
      ),
    ]);
  }

  final versionError = _versionError(document);
  if (versionError != null) {
    return _failure([versionError]);
  }

  final errors = <KeyboardMappingJsonError>[];
  final low = _readGroup('low', document, errors);
  final middle = _readGroup('middle', document, errors);
  final high = _readGroup('high', document, errors);
  if (errors.isNotEmpty || low == null || middle == null || high == null) {
    return _failure(errors);
  }

  final validation = MappingDraft(
    low: low,
    middle: middle,
    high: high,
  ).validate();
  if (!validation.isValid) {
    return KeyboardMappingJsonResult(
      mapping: null,
      errors: List.unmodifiable([
        for (final error in validation.errors) _keyError(error),
      ]),
      warnings: validation.warnings,
    );
  }

  return KeyboardMappingJsonResult(
    mapping: validation.mapping,
    errors: const [],
    warnings: validation.warnings,
  );
}

KeyboardMappingJsonResult _failure(List<KeyboardMappingJsonError> errors) {
  return KeyboardMappingJsonResult(
    mapping: null,
    errors: List.unmodifiable(errors),
    warnings: const [],
  );
}

Map<String, Object?>? _stringKeyMap(Object? json) {
  if (json is! Map) {
    return null;
  }
  final document = <String, Object?>{};
  for (final entry in json.entries) {
    if (entry.key is! String) {
      return null;
    }
    document[entry.key as String] = entry.value;
  }
  return document;
}

KeyboardMappingJsonError? _versionError(Map<String, Object?> document) {
  if (!document.containsKey('version')) {
    return const KeyboardMappingJsonError(
      issue: KeyboardMappingJsonIssue.missingField,
      field: 'version',
      message: '缺少 version。',
    );
  }
  final version = document['version'];
  if (version is! int) {
    return const KeyboardMappingJsonError(
      issue: KeyboardMappingJsonIssue.invalidType,
      field: 'version',
      message: 'version 必须是整数。',
    );
  }
  if (version != KeyboardMapping.jsonVersion) {
    return KeyboardMappingJsonError(
      issue: KeyboardMappingJsonIssue.unsupportedVersion,
      field: 'version',
      message: '不支持的键盘映射版本：$version。',
    );
  }
  return null;
}

List<String>? _readGroup(
  String field,
  Map<String, Object?> document,
  List<KeyboardMappingJsonError> errors,
) {
  if (!document.containsKey(field)) {
    errors.add(
      KeyboardMappingJsonError(
        issue: KeyboardMappingJsonIssue.missingField,
        field: field,
        message: '缺少 $field。',
      ),
    );
    return null;
  }
  final value = document[field];
  if (value is! List) {
    errors.add(
      KeyboardMappingJsonError(
        issue: KeyboardMappingJsonIssue.invalidType,
        field: field,
        message: '$field 必须是数组。',
      ),
    );
    return null;
  }

  final keys = <String>[];
  var itemsAreStrings = true;
  for (var index = 0; index < value.length; index++) {
    final item = value[index];
    if (item is! String) {
      itemsAreStrings = false;
      errors.add(
        KeyboardMappingJsonError(
          issue: KeyboardMappingJsonIssue.invalidKey,
          field: field,
          message: '$field 第 ${index + 1} 项必须是字符串。',
        ),
      );
      continue;
    }
    keys.add(item);
  }
  if (!itemsAreStrings) {
    return null;
  }
  return keys;
}

KeyboardMappingJsonError _keyError(MappingDraftError error) {
  final field = switch (error.register) {
    Register.low => 'low',
    Register.middle => 'middle',
    Register.high => 'high',
  };
  final issue = error.degree == null
      ? KeyboardMappingJsonIssue.invalidLength
      : KeyboardMappingJsonIssue.invalidKey;
  return KeyboardMappingJsonError(
    issue: issue,
    field: field,
    message: error.message,
  );
}
