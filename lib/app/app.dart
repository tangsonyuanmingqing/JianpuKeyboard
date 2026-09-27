import 'dart:ui' show AppExitResponse;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../features/converter/converter_page.dart';
import '../features/converter/converter_providers.dart';
import '../features/library/song_library_providers.dart';
import '../infrastructure/recovery_providers.dart';
import 'theme/app_theme.dart';
import 'theme/app_theme_mode.dart';

class JianpuKeyboardApp extends ConsumerStatefulWidget {
  const JianpuKeyboardApp({super.key});

  @override
  ConsumerState<JianpuKeyboardApp> createState() => _JianpuKeyboardAppState();
}

Future<AppExitResponse> handleAppExitRequest({
  required Future<void> Function() flush,
  required void Function() onFailure,
}) async {
  try {
    await flush();
    return AppExitResponse.exit;
  } on Object {
    onFailure();
    return AppExitResponse.cancel;
  }
}

class _JianpuKeyboardAppState extends ConsumerState<JianpuKeyboardApp> {
  final _messengerKey = GlobalKey<ScaffoldMessengerState>();
  late final AppLifecycleListener _lifecycleListener;

  @override
  void initState() {
    super.initState();
    _lifecycleListener = AppLifecycleListener(
      onExitRequested: _flushBeforeExit,
    );
  }

  Future<AppExitResponse> _flushBeforeExit() async {
    return handleAppExitRequest(
      flush: () async {
        await ref.read(converterInputProvider.notifier).flush();
        await ref.read(songLibraryPersistenceProvider).flush();
        await ref.read(recoverySnapshotRepositoryProvider).flush();
      },
      onFailure: () {
        _messengerKey.currentState?.showSnackBar(
          const SnackBar(content: Text('保存尚未完成，窗口暂未关闭。请重试。')),
        );
      },
    );
  }

  @override
  void dispose() {
    _lifecycleListener.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final mode = ref.watch(appThemeModeProvider);
    return MaterialApp(
      scaffoldMessengerKey: _messengerKey,
      title: '数字简谱键盘字母转换器',
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      themeMode: mode.materialThemeMode,
      home: const ConverterPage(),
    );
  }
}
