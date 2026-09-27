import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// A local visual preference shared by every interactive notation table.
class TableScale {
  static const minPercent = 0;
  static const maxPercent = 100;
  static const defaultPercent = 50;
  static const presets = <String, int>{
    '小': 0,
    '中': 50,
    '大': 100,
  };

  final int percent;

  const TableScale([this.percent = defaultPercent]);

  TableScale normalized() => TableScale(percent.clamp(minPercent, maxPercent));
  double get factor => .5 + normalized().percent / 200;
  String get presetLabel {
    for (final entry in presets.entries) {
      if (entry.value == percent) return entry.key;
    }
    return '自定义 $percent%';
  }

  String get displayLabel => '$presetLabel $percent%';

  double dimension(double base) => base * factor;
  double font(double base) => (base * factor).clamp(4.0, 48.0).toDouble();
}

class TableScalePersistence {
  static const storageKey = 'jianpu_keyboard.table_scale.v2';
  static const legacyStorageKey = 'jianpu_keyboard.table_scale.v1';
  SharedPreferencesAsync? _preferences;
  TableScalePersistence({SharedPreferencesAsync? preferences})
      : _preferences = preferences;
  SharedPreferencesAsync get _store =>
      _preferences ??= SharedPreferencesAsync();

  Future<TableScale> load() async {
    try {
      final raw = await _store.getString(storageKey);
      final decoded = raw == null ? null : jsonDecode(raw);
      if (decoded is Map && decoded['percent'] is int) {
        return TableScale(decoded['percent'] as int).normalized();
      }
      final legacyRaw = await _store.getString(legacyStorageKey);
      final legacyDecoded = legacyRaw == null ? null : jsonDecode(legacyRaw);
      if (legacyDecoded is Map && legacyDecoded['percent'] is int) {
        final migrated = _fromLegacyPercent(legacyDecoded['percent'] as int);
        await save(migrated);
        return migrated;
      }
    } on Object {
      // A missing visual preference falls back to the default table size.
    }
    return const TableScale();
  }

  Future<void> save(TableScale scale) async {
    try {
      await _store.setString(
        storageKey,
        jsonEncode({'percent': scale.normalized().percent}),
      );
    } on Object {
      // Keep the current session's visual setting when local storage fails.
    }
  }

  static TableScale _fromLegacyPercent(int legacyPercent) {
    if (legacyPercent <= 50) return const TableScale(0);
    if (legacyPercent >= 100) return const TableScale(100);
    return TableScale((legacyPercent - 50) * 2);
  }
}

final tableScalePersistenceProvider = Provider<TableScalePersistence>(
  (ref) => TableScalePersistence(),
);

final initialTableScaleProvider =
    Provider<TableScale>((ref) => const TableScale());

class TableScaleNotifier extends Notifier<TableScale> {
  @override
  TableScale build() => ref.read(initialTableScaleProvider);

  void setPercent(num value) {
    final next = TableScale(value.round()).normalized();
    if (next.percent == state.percent) return;
    state = next;
    ref.read(tableScalePersistenceProvider).save(next);
  }
}

final tableScaleProvider = NotifierProvider<TableScaleNotifier, TableScale>(
  TableScaleNotifier.new,
);

class GlobalTableScaleControl extends ConsumerStatefulWidget {
  const GlobalTableScaleControl({super.key});

  @override
  ConsumerState<GlobalTableScaleControl> createState() =>
      _GlobalTableScaleControlState();
}

class _GlobalTableScaleControlState
    extends ConsumerState<GlobalTableScaleControl> {
  final _percentageController = TextEditingController();
  final _percentageFocusNode = FocusNode();
  String? _error;

  @override
  void dispose() {
    _percentageController.dispose();
    _percentageFocusNode.dispose();
    super.dispose();
  }

  void _submit(String value) {
    final parsed = int.tryParse(value.trim());
    if (parsed == null ||
        parsed < TableScale.minPercent ||
        parsed > TableScale.maxPercent) {
      setState(() =>
          _error = '请输入 ${TableScale.minPercent}–${TableScale.maxPercent} 的整数');
      return;
    }
    ref.read(tableScaleProvider.notifier).setPercent(parsed);
    setState(() => _error = null);
    FocusScope.of(context).unfocus();
  }

  @override
  Widget build(BuildContext context) {
    final scale = ref.watch(tableScaleProvider);
    final selection = TableScale.presets.entries
            .where((entry) => entry.value == scale.percent)
            .map((entry) => entry.key)
            .firstOrNull ??
        'custom';
    if (!_percentageFocusNode.hasFocus &&
        (!_percentageController.selection.isValid ||
            _percentageController.text != '${scale.percent}')) {
      _percentageController.value = TextEditingValue(
        text: '${scale.percent}',
        selection: TextSelection.collapsed(offset: '${scale.percent}'.length),
      );
    }
    return Wrap(
      spacing: 8,
      runSpacing: 6,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Text(
          '全局表格大小',
          style: Theme.of(context).textTheme.titleSmall,
        ),
        DropdownButton<String>(
          value: selection,
          onChanged: (value) {
            if (value == null || value == 'custom') return;
            ref
                .read(tableScaleProvider.notifier)
                .setPercent(TableScale.presets[value]!);
          },
          items: [
            for (final entry in TableScale.presets.entries)
              DropdownMenuItem(
                  value: entry.key,
                  child: Text('${entry.key} ${entry.value}%')),
            if (selection == 'custom')
              DropdownMenuItem(
                  value: 'custom', child: Text('自定义 ${scale.percent}%')),
          ],
        ),
        IconButton(
          tooltip: '缩小 1%',
          onPressed: scale.percent <= TableScale.minPercent
              ? null
              : () => ref
                  .read(tableScaleProvider.notifier)
                  .setPercent(scale.percent - 1),
          icon: const Icon(Icons.remove),
        ),
        SizedBox(
          width: 180,
          child: Slider(
            value: scale.percent.toDouble(),
            min: TableScale.minPercent.toDouble(),
            max: TableScale.maxPercent.toDouble(),
            divisions: TableScale.maxPercent - TableScale.minPercent,
            label: '${scale.percent}%',
            onChanged: (value) =>
                ref.read(tableScaleProvider.notifier).setPercent(value),
          ),
        ),
        IconButton(
          tooltip: '放大 1%',
          onPressed: scale.percent >= TableScale.maxPercent
              ? null
              : () => ref
                  .read(tableScaleProvider.notifier)
                  .setPercent(scale.percent + 1),
          icon: const Icon(Icons.add),
        ),
        SizedBox(
          width: 70,
          child: TextField(
            controller: _percentageController,
            focusNode: _percentageFocusNode,
            keyboardType: TextInputType.number,
            textInputAction: TextInputAction.done,
            onSubmitted: _submit,
            decoration: InputDecoration(
              suffixText: '%',
              isDense: true,
              errorText: _error,
              border: const OutlineInputBorder(),
            ),
          ),
        ),
      ],
    );
  }
}

extension<T> on Iterable<T> {
  T? get firstOrNull {
    final iterator = this.iterator;
    return iterator.moveNext() ? iterator.current : null;
  }
}
