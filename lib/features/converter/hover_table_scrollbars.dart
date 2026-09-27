import 'dart:async';

import 'package:flutter/material.dart';

typedef HoverTableScrollbarBuilder = Widget Function(
  BuildContext context,
  bool showHorizontal,
  bool showVertical,
);

/// Reveals table scrollbars only while their edge rail is in use.
///
/// The builder owns the actual [Scrollbar] widgets, which keeps this class
/// independent from the scrollable layout and its notification predicates.
class HoverTableScrollbars extends StatefulWidget {
  const HoverTableScrollbars({
    super.key,
    required this.horizontalController,
    required this.verticalController,
    required this.builder,
    this.hotZoneExtent = 16,
    this.hideDelay = const Duration(milliseconds: 800),
  });

  final ScrollController horizontalController;
  final ScrollController verticalController;
  final HoverTableScrollbarBuilder builder;
  final double hotZoneExtent;
  final Duration hideDelay;

  @override
  State<HoverTableScrollbars> createState() => _HoverTableScrollbarsState();
}

class _HoverTableScrollbarsState extends State<HoverTableScrollbars> {
  Timer? _horizontalHideTimer;
  Timer? _verticalHideTimer;
  var _showHorizontal = false;
  var _showVertical = false;
  var _draggingHorizontal = false;
  var _draggingVertical = false;
  var _pointerInsidePanel = false;
  Offset? _lastPointerPosition;

  @override
  void didUpdateWidget(covariant HoverTableScrollbars oldWidget) {
    super.didUpdateWidget(oldWidget);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_pointerInsidePanel) return;
      final position = _lastPointerPosition;
      final renderObject = context.findRenderObject();
      if (position == null ||
          renderObject is! RenderBox ||
          !renderObject.hasSize) {
        return;
      }
      _handlePanelHover(position, renderObject.size);
    });
  }

  @override
  void dispose() {
    _horizontalHideTimer?.cancel();
    _verticalHideTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final size = Size(constraints.maxWidth, constraints.maxHeight);
        return MouseRegion(
          onEnter: (event) => _handlePanelEnter(event.localPosition, size),
          onHover: (event) => _handlePanelHover(event.localPosition, size),
          onExit: (_) => _handlePanelExit(),
          child: Listener(
            behavior: HitTestBehavior.translucent,
            onPointerDown: (event) => _handlePanelPointerDown(event, size),
            onPointerUp: (event) => _handlePanelPointerUp(event, size),
            onPointerCancel: (_) => _stopDraggingAndScheduleHide(),
            child: widget.builder(
              context,
              _showHorizontal && _canScroll(widget.horizontalController),
              _showVertical && _canScroll(widget.verticalController),
            ),
          ),
        );
      },
    );
  }

  bool _canScroll(ScrollController controller) =>
      controller.hasClients && controller.position.maxScrollExtent > 0;

  void _handlePanelEnter(Offset position, Size size) {
    _pointerInsidePanel = true;
    _handlePanelHover(position, size);
  }

  void _handlePanelHover(Offset position, Size size) {
    _pointerInsidePanel = true;
    _lastPointerPosition = position;
    _updateAxis(
      horizontal: true,
      active: _isInHorizontalZone(position, size) || _draggingHorizontal,
    );
    _updateAxis(
      horizontal: false,
      active: _isInVerticalZone(position, size) || _draggingVertical,
    );
  }

  void _handlePanelExit() {
    _pointerInsidePanel = false;
    _scheduleHorizontalHide();
    _scheduleVerticalHide();
  }

  void _handlePanelPointerDown(PointerDownEvent event, Size size) {
    final inHorizontalZone = _isInHorizontalZone(event.localPosition, size);
    final inVerticalZone = _isInVerticalZone(event.localPosition, size);
    if (inHorizontalZone) _draggingHorizontal = true;
    if (inVerticalZone) _draggingVertical = true;
    _handlePanelHover(event.localPosition, size);
  }

  void _handlePanelPointerUp(PointerUpEvent event, Size size) {
    _draggingHorizontal = false;
    _draggingVertical = false;
    _handlePanelHover(event.localPosition, size);
  }

  void _stopDraggingAndScheduleHide() {
    _draggingHorizontal = false;
    _draggingVertical = false;
    _scheduleHorizontalHide();
    _scheduleVerticalHide();
  }

  void _scheduleHorizontalHide() {
    _updateAxis(horizontal: true, active: _draggingHorizontal);
  }

  void _scheduleVerticalHide() {
    _updateAxis(horizontal: false, active: _draggingVertical);
  }

  bool _isInHorizontalZone(Offset position, Size size) =>
      size.height.isFinite &&
      position.dx >= 0 &&
      position.dx <= size.width &&
      position.dy >= size.height - widget.hotZoneExtent &&
      position.dy <= size.height;

  bool _isInVerticalZone(Offset position, Size size) =>
      size.width.isFinite &&
      position.dy >= 0 &&
      position.dy <= size.height &&
      position.dx >= size.width - widget.hotZoneExtent &&
      position.dx <= size.width;

  void _updateAxis({required bool horizontal, required bool active}) {
    final timer = horizontal ? _horizontalHideTimer : _verticalHideTimer;
    if (active) {
      timer?.cancel();
      _setVisible(horizontal, true);
      return;
    }
    final visible = horizontal ? _showHorizontal : _showVertical;
    if (!visible || timer?.isActive == true) return;
    final hideTimer = Timer(widget.hideDelay, () {
      if (!mounted) return;
      _setVisible(horizontal, false);
    });
    if (horizontal) {
      _horizontalHideTimer = hideTimer;
    } else {
      _verticalHideTimer = hideTimer;
    }
  }

  void _setVisible(bool horizontal, bool visible) {
    if (horizontal ? _showHorizontal == visible : _showVertical == visible) {
      return;
    }
    setState(() {
      if (horizontal) {
        _showHorizontal = visible;
      } else {
        _showVertical = visible;
      }
    });
  }
}
