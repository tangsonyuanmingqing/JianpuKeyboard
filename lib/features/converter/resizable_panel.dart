import 'package:flutter/material.dart';

/// The size a user has chosen for one converter panel.
///
/// A null width means "use all available width". This lets a reset panel
/// continue to follow the app window instead of persisting a stale pixel size.
class ResizablePanelSize {
  final double? width;
  final double? height;

  const ResizablePanelSize({this.width, this.height});

  bool get isDefault => width == null && height == null;

  Map<String, Object> toJson() => {
        if (width != null) 'width': width!,
        if (height != null) 'height': height!,
      };

  static ResizablePanelSize? fromJson(Object? value) {
    if (value is! Map) return null;
    final rawWidth = value['width'];
    final rawHeight = value['height'];
    final width = rawWidth is num ? rawWidth.toDouble() : null;
    final height = rawHeight is num ? rawHeight.toDouble() : null;
    if (width != null && !width.isFinite ||
        height != null && !height.isFinite) {
      return null;
    }
    return ResizablePanelSize(width: width, height: height);
  }
}

/// A bounded panel with a bottom-right resize grip.
///
/// Its parent owns persistence. The widget only reports a new size when a
/// drag ends, so a resize does not write preferences for every pointer move.
class ResizablePanel extends StatefulWidget {
  static const defaultHeight = 360.0;
  static const minWidth = 320.0;
  static const minHeight = 160.0;
  static const maxHeight = 1200.0;

  final String panelId;
  final ResizablePanelSize size;
  final ValueChanged<ResizablePanelSize> onSizeChanged;
  final Widget child;
  final double initialHeight;

  const ResizablePanel({
    super.key,
    required this.panelId,
    required this.size,
    required this.onSizeChanged,
    required this.child,
    this.initialHeight = ResizablePanel.defaultHeight,
  });

  @override
  State<ResizablePanel> createState() => _ResizablePanelState();
}

class _ResizablePanelState extends State<ResizablePanel> {
  double? _dragWidth;
  double? _dragHeight;
  bool _dragging = false;

  @override
  void didUpdateWidget(covariant ResizablePanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_dragging && oldWidget.size != widget.size) {
      _dragWidth = null;
      _dragHeight = null;
    }
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final availableWidth = constraints.maxWidth.isFinite
            ? constraints.maxWidth
            : ResizablePanel.minWidth;
        final width = _clampWidth(
          _dragWidth ?? widget.size.width ?? availableWidth,
          availableWidth,
        );
        final height = _clampHeight(
          _dragHeight ?? widget.size.height ?? widget.initialHeight,
        );
        return Align(
          alignment: Alignment.topLeft,
          child: SizedBox(
            key: Key('resizable-panel-${widget.panelId}'),
            width: width,
            height: height,
            child: Stack(
              fit: StackFit.expand,
              children: [
                widget.child,
                Positioned(
                  right: 0,
                  bottom: 0,
                  child: _ResizeGrip(
                    key: Key('${widget.panelId}-resize-handle'),
                    onStart: _startResize,
                    onUpdate: (delta) => _resize(delta, availableWidth),
                    onEnd: () => _finishResize(width, height, availableWidth),
                    onReset: _reset,
                  ),
                ),
                if (_dragging)
                  Positioned(
                    right: 24,
                    bottom: 8,
                    child: IgnorePointer(
                      child: Material(
                        color: Theme.of(context).colorScheme.inverseSurface,
                        borderRadius: BorderRadius.circular(4),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 3),
                          child: Text(
                            '${width.round()} × ${height.round()}',
                            key: Key('${widget.panelId}-resize-dimensions'),
                            style: TextStyle(
                              color: Theme.of(context)
                                  .colorScheme
                                  .onInverseSurface,
                              fontSize: 12,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _resize(Offset delta, double availableWidth) {
    setState(() {
      final currentWidth = _clampWidth(
        _dragWidth ?? widget.size.width ?? availableWidth,
        availableWidth,
      );
      final currentHeight = _clampHeight(
        _dragHeight ?? widget.size.height ?? widget.initialHeight,
      );
      _dragWidth = _clampWidth(currentWidth + delta.dx, availableWidth);
      _dragHeight = _clampHeight(currentHeight + delta.dy);
    });
  }

  void _startResize() => setState(() => _dragging = true);

  void _finishResize(double width, double height, double availableWidth) {
    final savedWidth = _clampWidth(
      _dragWidth ?? width,
      availableWidth,
    );
    final savedHeight = _clampHeight(_dragHeight ?? height);
    setState(() {
      _dragging = false;
      _dragWidth = null;
      _dragHeight = null;
    });
    widget.onSizeChanged(
      ResizablePanelSize(width: savedWidth, height: savedHeight),
    );
  }

  void _reset() {
    setState(() {
      _dragging = false;
      _dragWidth = null;
      _dragHeight = null;
    });
    widget.onSizeChanged(const ResizablePanelSize());
  }

  double _clampWidth(double width, double availableWidth) {
    final minimum = availableWidth < ResizablePanel.minWidth
        ? availableWidth
        : ResizablePanel.minWidth;
    return width.clamp(minimum, availableWidth);
  }

  double _clampHeight(double height) =>
      height.clamp(ResizablePanel.minHeight, ResizablePanel.maxHeight);
}

class _ResizeGrip extends StatelessWidget {
  final VoidCallback onStart;
  final ValueChanged<Offset> onUpdate;
  final VoidCallback onEnd;
  final VoidCallback onReset;

  const _ResizeGrip({
    super.key,
    required this.onStart,
    required this.onUpdate,
    required this.onEnd,
    required this.onReset,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: '拖动调整大小，双击恢复默认大小',
      child: MouseRegion(
        cursor: SystemMouseCursors.resizeUpLeftDownRight,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onDoubleTap: onReset,
          onPanStart: (_) => onStart(),
          onPanUpdate: (details) => onUpdate(details.delta),
          onPanEnd: (_) => onEnd(),
          child: SizedBox(
            width: 24,
            height: 24,
            child: CustomPaint(
              painter: _GripPainter(
                Theme.of(context).colorScheme.outline,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _GripPainter extends CustomPainter {
  final Color color;

  const _GripPainter(this.color);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color.withValues(alpha: .75)
      ..strokeWidth = 1.4
      ..strokeCap = StrokeCap.round;
    for (var offset = 6.0; offset <= 16; offset += 5) {
      canvas.drawLine(Offset(offset, 20), Offset(20, offset), paint);
    }
  }

  @override
  bool shouldRepaint(covariant _GripPainter oldDelegate) =>
      oldDelegate.color != color;
}
