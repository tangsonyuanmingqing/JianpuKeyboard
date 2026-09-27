import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// A borderless grid editor with Flutter's platform-aware text gestures.
/// The cell supplies decoration, validation indicators and its own shortcuts;
/// Material form, decoration and counter machinery is not needed here.
class SmartGridTextField extends StatefulWidget {
  const SmartGridTextField({
    super.key,
    required this.controller,
    required this.focusNode,
    required this.style,
    required this.onTap,
    required this.onSubmitted,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final TextStyle style;
  final VoidCallback onTap;
  final ValueChanged<String> onSubmitted;

  @override
  State<SmartGridTextField> createState() => _SmartGridTextFieldState();
}

class _SmartGridTextFieldState extends State<SmartGridTextField>
    implements TextSelectionGestureDetectorBuilderDelegate {
  @override
  final editableTextKey = GlobalKey<EditableTextState>();

  @override
  bool get forcePressEnabled => false;

  @override
  bool get selectionEnabled => false;

  late final _gestures = _GridTextGestures(this);

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return MouseRegion(
      cursor: SystemMouseCursors.text,
      child: _gestures.buildGestureDetector(
        behavior: HitTestBehavior.opaque,
        child: Align(
          alignment: Alignment.center,
          child: EditableText(
            key: editableTextKey,
            controller: widget.controller,
            focusNode: widget.focusNode,
            style: widget.style.copyWith(color: colors.onSurface),
            cursorColor: colors.primary,
            backgroundCursorColor: colors.onSurfaceVariant,
            textAlign: TextAlign.center,
            maxLines: 1,
            enableInteractiveSelection: false,
            rendererIgnoresPointer: true,
            onSubmitted: widget.onSubmitted,
            inputFormatters: [
              FilteringTextInputFormatter.deny(RegExp(r'[\r\n\t]')),
            ],
          ),
        ),
      ),
    );
  }
}

class _GridTextGestures extends TextSelectionGestureDetectorBuilder {
  _GridTextGestures(this.state) : super(delegate: state);

  final _SmartGridTextFieldState state;

  @override
  bool get onUserTapAlwaysCalled => true;

  @override
  void onUserTap() => state.widget.onTap();
}
