import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/mapping/mapping_draft.dart';
import '../../core/models/register.dart';
import 'converter_providers.dart';

/// Key for the single-letter field of [degree] in [register].
Key mappingFieldKey(Register register, int degree) {
  return Key('mapping-field-${register.name}-$degree');
}

/// Edits the in-memory keyboard mapping draft.
class MappingPage extends ConsumerStatefulWidget {
  const MappingPage({super.key});

  @override
  ConsumerState<MappingPage> createState() => _MappingPageState();
}

class _MappingPageState extends ConsumerState<MappingPage> {
  static const _degrees = [1, 2, 3, 4, 5, 6, 7];
  static const _wideLayoutWidth = 720.0;

  late final Map<String, TextEditingController> _controllers;

  @override
  void initState() {
    super.initState();
    final draft = ref.read(mappingDraftProvider);
    _controllers = {
      for (final register in Register.values)
        for (final degree in _degrees)
          _slot(register, degree): TextEditingController(
            text: _valueAt(draft, register, degree),
          ),
    };
  }

  @override
  void dispose() {
    for (final controller in _controllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(mappingDraftProvider, (previous, next) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) {
          return;
        }
        _syncControllers(next);
      });
    });

    final draft = ref.watch(mappingDraftProvider);
    final mappingMessage = ref.watch(mappingPersistenceMessageProvider);
    final validation = draft.validate();
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('键盘映射'),
      ),
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final wide = constraints.maxWidth >= _wideLayoutWidth;
            return SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (mappingMessage != null) ...[
                    Text(
                      mappingMessage,
                      key: const Key('mapping-persistence-message'),
                      style: TextStyle(color: theme.colorScheme.error),
                    ),
                    const SizedBox(height: 12),
                  ],
                  if (validation.errors.isNotEmpty) ...[
                    Text(
                      '键位有误，当前修改不会保存。',
                      key: const Key('mapping-unsaved-message'),
                      style: TextStyle(color: theme.colorScheme.error),
                    ),
                    const SizedBox(height: 12),
                  ],
                  if (validation.warnings.isNotEmpty) ...[
                    for (final warning in validation.warnings)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Text(
                          '⚠ ${warning.message}',
                          key: Key('mapping-warning-${warning.key}'),
                          style: TextStyle(color: theme.colorScheme.tertiary),
                        ),
                      ),
                    const SizedBox(height: 4),
                  ],
                  Align(
                    alignment: Alignment.centerLeft,
                    child: OutlinedButton(
                      key: const Key('restore-mapping-button'),
                      onPressed: () {
                        ref
                            .read(mappingDraftProvider.notifier)
                            .restoreDefault();
                      },
                      child: const Text('恢复默认'),
                    ),
                  ),
                  const SizedBox(height: 16),
                  _groups(
                    wide: wide,
                    draft: draft,
                    validation: validation,
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _groups({
    required bool wide,
    required MappingDraft draft,
    required MappingDraftValidation validation,
  }) {
    final sections = [
      for (final register in Register.values)
        _RegisterSection(
          register: register,
          draft: draft,
          validation: validation,
          controllers: _controllers,
          onChanged: _setKey,
        ),
    ];
    if (!wide) {
      return Column(
        children: [
          for (var index = 0; index < sections.length; index++) ...[
            if (index > 0) const SizedBox(height: 12),
            sections[index],
          ],
        ],
      );
    }
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var index = 0; index < sections.length; index++) ...[
          if (index > 0) const SizedBox(width: 12),
          Expanded(child: sections[index]),
        ],
      ],
    );
  }

  void _setKey(Register register, int degree, String raw) {
    final value = _storedKeyText(raw);
    final controller = _controllers[_slot(register, degree)]!;
    if (controller.text != value) {
      controller.value = TextEditingValue(
        text: value,
        selection: TextSelection.collapsed(offset: value.length),
      );
    }
    final draft = ref.read(mappingDraftProvider);
    ref.read(mappingDraftProvider.notifier).updateMapping(
          _withValue(draft, register, degree, value),
        );
  }

  void _syncControllers(MappingDraft draft) {
    for (final register in Register.values) {
      for (final degree in _degrees) {
        final controller = _controllers[_slot(register, degree)]!;
        final value = _valueAt(draft, register, degree);
        if (controller.text != value) {
          controller.text = value;
        }
      }
    }
  }
}

class _RegisterSection extends StatelessWidget {
  final Register register;
  final MappingDraft draft;
  final MappingDraftValidation validation;
  final Map<String, TextEditingController> controllers;
  final void Function(Register register, int degree, String value) onChanged;

  const _RegisterSection({
    required this.register,
    required this.draft,
    required this.validation,
    required this.controllers,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final groupErrors = [
      for (final error in validation.errors)
        if (error.register == register && error.degree == null) error,
    ];

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        border: Border.all(color: theme.colorScheme.outlineVariant),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            _registerLabel(register),
            style: theme.textTheme.titleMedium,
          ),
          for (final error in groupErrors) ...[
            const SizedBox(height: 8),
            Text(
              error.message,
              style: TextStyle(color: theme.colorScheme.error),
            ),
          ],
          const SizedBox(height: 8),
          for (final degree in _MappingPageState._degrees) ...[
            _KeyField(
              register: register,
              degree: degree,
              controller: controllers[_slot(register, degree)]!,
              error: _fieldError(validation, register, degree),
              warningText: _fieldWarning(draft, validation, register, degree),
              onChanged: (value) => onChanged(register, degree, value),
            ),
            const SizedBox(height: 8),
          ],
        ],
      ),
    );
  }
}

class _KeyField extends StatelessWidget {
  final Register register;
  final int degree;
  final TextEditingController controller;
  final MappingDraftError? error;
  final String? warningText;
  final ValueChanged<String> onChanged;

  const _KeyField({
    required this.register,
    required this.degree,
    required this.controller,
    required this.error,
    required this.warningText,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final borderColor = error != null
        ? theme.colorScheme.error
        : warningText != null
            ? theme.colorScheme.tertiary
            : theme.colorScheme.outline;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            SizedBox(
              width: 20,
              child: Text('$degree'),
            ),
            const SizedBox(width: 8),
            SizedBox(
              width: 64,
              child: TextField(
                key: mappingFieldKey(register, degree),
                controller: controller,
                onChanged: onChanged,
                textAlign: TextAlign.center,
                maxLines: 1,
                autocorrect: false,
                enableSuggestions: false,
                textCapitalization: TextCapitalization.characters,
                decoration: InputDecoration(
                  isDense: true,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 12,
                  ),
                  border: const OutlineInputBorder(),
                  enabledBorder: OutlineInputBorder(
                    borderSide: BorderSide(color: borderColor),
                  ),
                ),
              ),
            ),
          ],
        ),
        if (error != null) ...[
          const SizedBox(height: 4),
          Text(
            _errorLabel(error!),
            key: Key('mapping-error-${register.name}-$degree'),
            style: TextStyle(color: theme.colorScheme.error),
          ),
        ],
        if (warningText != null) ...[
          const SizedBox(height: 4),
          Text(
            warningText!,
            style: TextStyle(color: theme.colorScheme.tertiary),
          ),
        ],
      ],
    );
  }
}

String _slot(Register register, int degree) => '${register.name}-$degree';

String _registerLabel(Register register) {
  return switch (register) {
    Register.low => '低音',
    Register.middle => '中音',
    Register.high => '高音',
  };
}

String _valueAt(MappingDraft draft, Register register, int degree) {
  final keys = switch (register) {
    Register.low => draft.low,
    Register.middle => draft.middle,
    Register.high => draft.high,
  };
  final index = degree - 1;
  if (keys == null || index >= keys.length) {
    return '';
  }
  return keys[index];
}

String _storedKeyText(String value) {
  if (value.length != 1) {
    return value;
  }
  final upper = value.toUpperCase();
  if (upper != value.toLowerCase()) {
    return upper;
  }
  return value;
}

String _errorLabel(MappingDraftError error) {
  if (error.value.isEmpty && error.degree != null) {
    return '${_registerLabel(error.register)} ${error.degree}：请输入 A-Z 字母';
  }
  return error.message;
}

MappingDraftError? _fieldError(
  MappingDraftValidation validation,
  Register register,
  int degree,
) {
  for (final error in validation.errors) {
    if (error.register == register && error.degree == degree) {
      return error;
    }
  }
  return null;
}

String? _fieldWarning(
  MappingDraft draft,
  MappingDraftValidation validation,
  Register register,
  int degree,
) {
  final value = _valueAt(draft, register, degree);
  if (value.length != 1) {
    return null;
  }
  final letter = value.toUpperCase();
  for (final warning in validation.warnings) {
    if (warning.key == letter) {
      return '⚠ ${warning.message}';
    }
  }
  return null;
}

MappingDraft _withValue(
  MappingDraft draft,
  Register register,
  int degree,
  String value,
) {
  final low = _editableGroup(draft.low);
  final middle = _editableGroup(draft.middle);
  final high = _editableGroup(draft.high);
  final group = switch (register) {
    Register.low => low,
    Register.middle => middle,
    Register.high => high,
  };
  group[degree - 1] = value;
  return MappingDraft(low: low, middle: middle, high: high);
}

List<String> _editableGroup(List<String>? keys) {
  final group = List<String>.filled(7, '');
  if (keys == null) {
    return group;
  }
  for (var index = 0; index < keys.length && index < group.length; index++) {
    group[index] = keys[index];
  }
  return group;
}
