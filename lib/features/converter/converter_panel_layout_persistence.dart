import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'resizable_panel.dart';

/// Stores converter panel sizes as a global UI preference, separate from song
/// drafts and conversion content.
class ConverterPanelLayoutPersistence {
  static const _key = 'jianpu_keyboard.converter_panel_layout.v1';

  SharedPreferencesAsync? _preferences;

  ConverterPanelLayoutPersistence({SharedPreferencesAsync? preferences})
      : _preferences = preferences;

  SharedPreferencesAsync get _store =>
      _preferences ??= SharedPreferencesAsync();

  Future<Map<String, ResizablePanelSize>> load() async {
    try {
      final raw = await _store.getString(_key);
      if (raw == null) return const {};
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return const {};
      final sizes = <String, ResizablePanelSize>{};
      decoded.forEach((key, value) {
        if (key is! String) return;
        final size = ResizablePanelSize.fromJson(value);
        if (size != null && !size.isDefault) sizes[key] = size;
      });
      return sizes;
    } on Object {
      return const {};
    }
  }

  Future<void> save(Map<String, ResizablePanelSize> sizes) async {
    final stored = <String, Object>{
      for (final entry in sizes.entries)
        if (!entry.value.isDefault) entry.key: entry.value.toJson(),
    };
    try {
      await _store.setString(_key, jsonEncode(stored));
    } on Object {
      // A panel size is a recoverable visual preference. The current session
      // still keeps the new size when the operating system store is absent.
    }
  }
}
