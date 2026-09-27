import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The two application-owned appearance modes. System brightness is not used.
enum AppThemeMode {
  light,
  dark;

  ThemeMode get materialThemeMode => switch (this) {
        AppThemeMode.light => ThemeMode.light,
        AppThemeMode.dark => ThemeMode.dark,
      };
}

/// Persists visual appearance separately from song and converter content.
class ThemePreferencePersistence {
  static const storageKey = 'jianpu_keyboard.theme_mode.v1';

  SharedPreferencesAsync? _preferences;

  ThemePreferencePersistence({SharedPreferencesAsync? preferences})
      : _preferences = preferences;

  SharedPreferencesAsync get _store =>
      _preferences ??= SharedPreferencesAsync();

  Future<AppThemeMode> load() async {
    try {
      return switch (await _store.getString(storageKey)) {
        'dark' => AppThemeMode.dark,
        _ => AppThemeMode.light,
      };
    } on Object {
      return AppThemeMode.light;
    }
  }

  Future<void> save(AppThemeMode mode) async {
    try {
      await _store.setString(storageKey, mode.name);
    } on Object {
      // The active session keeps the user's choice if local storage fails.
    }
  }
}

final themePreferencePersistenceProvider =
    Provider<ThemePreferencePersistence>((ref) => ThemePreferencePersistence());

final initialThemeModeProvider =
    Provider<AppThemeMode>((ref) => AppThemeMode.light);

class AppThemeModeNotifier extends Notifier<AppThemeMode> {
  @override
  AppThemeMode build() => ref.read(initialThemeModeProvider);

  void toggle() {
    state = switch (state) {
      AppThemeMode.light => AppThemeMode.dark,
      AppThemeMode.dark => AppThemeMode.light,
    };
    ref.read(themePreferencePersistenceProvider).save(state);
  }
}

final appThemeModeProvider =
    NotifierProvider<AppThemeModeNotifier, AppThemeMode>(
  AppThemeModeNotifier.new,
);

/// A shared AppBar action available from every application page.
class ThemeToggleButton extends ConsumerWidget {
  const ThemeToggleButton({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mode = ref.watch(appThemeModeProvider);
    final dark = mode == AppThemeMode.dark;
    return IconButton(
      key: const Key('theme-toggle-button'),
      tooltip: dark ? '切换白色主题' : '切换黑色主题',
      onPressed: () => ref.read(appThemeModeProvider.notifier).toggle(),
      icon: Icon(dark ? Icons.light_mode : Icons.dark_mode),
    );
  }
}
