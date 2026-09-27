import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jianpu_keyboard/app/theme/app_theme.dart';
import 'package:jianpu_keyboard/app/theme/app_theme_mode.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('theme preference defaults safely to light and restores dark', () async {
    final preferences = _PreferencesFake();
    final persistence = ThemePreferencePersistence(preferences: preferences);

    expect(await persistence.load(), AppThemeMode.light);

    preferences.values[ThemePreferencePersistence.storageKey] = 'unknown';
    expect(await persistence.load(), AppThemeMode.light);

    await persistence.save(AppThemeMode.dark);
    expect(preferences.values[ThemePreferencePersistence.storageKey], 'dark');
    expect(await persistence.load(), AppThemeMode.dark);
  });

  testWidgets('theme action immediately switches the active application theme',
      (tester) async {
    final preferences = _PreferencesFake();
    final container = ProviderContainer(overrides: [
      themePreferencePersistenceProvider.overrideWithValue(
        ThemePreferencePersistence(preferences: preferences),
      ),
    ]);
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const _ThemeHarness(),
      ),
    );

    expect(find.text('light'), findsOneWidget);
    expect(find.byTooltip('切换黑色主题'), findsOneWidget);

    await tester.tap(find.byKey(const Key('theme-toggle-button')));
    await tester.pumpAndSettle();

    expect(find.text('dark'), findsOneWidget);
    expect(find.byTooltip('切换白色主题'), findsOneWidget);
    expect(container.read(appThemeModeProvider), AppThemeMode.dark);
    expect(preferences.values[ThemePreferencePersistence.storageKey], 'dark');
  });
}

class _ThemeHarness extends ConsumerWidget {
  const _ThemeHarness();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mode = ref.watch(appThemeModeProvider);
    return MaterialApp(
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      themeMode: mode.materialThemeMode,
      home: Scaffold(
        appBar: AppBar(actions: const [ThemeToggleButton()]),
        body: Builder(
          builder: (context) => Text(
            Theme.of(context).brightness == Brightness.dark ? 'dark' : 'light',
          ),
        ),
      ),
    );
  }
}

class _PreferencesFake extends Fake implements SharedPreferencesAsync {
  final values = <String, String>{};

  @override
  Future<String?> getString(String key) async => values[key];

  @override
  Future<void> setString(String key, String value) async {
    values[key] = value;
  }
}
