import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Bridges the Windows runner's top-level window controls to Flutter.
abstract class WindowPinPlatform {
  const WindowPinPlatform();

  bool get isSupported;

  Future<void> setAlwaysOnTop(bool enabled);
}

class MethodChannelWindowPinPlatform extends WindowPinPlatform {
  const MethodChannelWindowPinPlatform();

  static const _channel = MethodChannel('jianpu_keyboard/window');

  @override
  bool get isSupported => defaultTargetPlatform == TargetPlatform.windows;

  @override
  Future<void> setAlwaysOnTop(bool enabled) async {
    if (!isSupported) {
      return;
    }
    final success = await _channel.invokeMethod<bool>(
      'setAlwaysOnTop',
      {'enabled': enabled},
    );
    if (success != true) {
      throw PlatformException(
        code: 'window_pin_failed',
        message: 'Windows runner did not confirm the window pin state.',
      );
    }
  }
}

final windowPinPlatformProvider = Provider<WindowPinPlatform>(
  (ref) => const MethodChannelWindowPinPlatform(),
);

class WindowPinState {
  const WindowPinState({this.isPinned = false, this.isUpdating = false});

  final bool isPinned;
  final bool isUpdating;

  WindowPinState copyWith({bool? isPinned, bool? isUpdating}) {
    return WindowPinState(
      isPinned: isPinned ?? this.isPinned,
      isUpdating: isUpdating ?? this.isUpdating,
    );
  }
}

class WindowPinNotifier extends Notifier<WindowPinState> {
  @override
  WindowPinState build() => const WindowPinState();

  Future<bool> toggle() async {
    if (state.isUpdating || !ref.read(windowPinPlatformProvider).isSupported) {
      return false;
    }

    final target = !state.isPinned;
    state = state.copyWith(isUpdating: true);
    try {
      await ref.read(windowPinPlatformProvider).setAlwaysOnTop(target);
      state = WindowPinState(isPinned: target);
      return true;
    } on Object {
      state = state.copyWith(isUpdating: false);
      return false;
    }
  }
}

final windowPinProvider =
    NotifierProvider<WindowPinNotifier, WindowPinState>(WindowPinNotifier.new);

/// Shared right-most AppBar action for Windows-only top-most window control.
class WindowPinToggleButton extends ConsumerWidget {
  const WindowPinToggleButton({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final platform = ref.watch(windowPinPlatformProvider);
    if (!platform.isSupported) {
      return const SizedBox.shrink();
    }
    final state = ref.watch(windowPinProvider);
    return IconButton(
      key: const Key('window-pin-toggle-button'),
      tooltip: state.isPinned ? '取消窗口置顶' : '开启窗口置顶',
      onPressed: state.isUpdating
          ? null
          : () async {
              final wasPinned = state.isPinned;
              final succeeded =
                  await ref.read(windowPinProvider.notifier).toggle();
              if (!context.mounted) {
                return;
              }
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(
                    succeeded
                        ? (wasPinned ? '已关闭窗口置顶' : '已开启窗口置顶')
                        : '窗口置顶设置失败，请重试',
                  ),
                ),
              );
            },
      icon: Icon(
        state.isPinned ? Icons.push_pin : Icons.push_pin_outlined,
        color: state.isPinned ? Theme.of(context).colorScheme.primary : null,
      ),
    );
  }
}
