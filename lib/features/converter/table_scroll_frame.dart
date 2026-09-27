import 'package:flutter/material.dart';

/// Table-only scroll chrome. Controllers and content remain caller-owned.
///
/// The content and the two rails are siblings: scrollbars cannot cover cells,
/// headers or ResizablePanel's lower-right grip. Only the supplied positions
/// can relay metrics to the rails; nested editors and frozen panes are ignored.
class TableScrollFrame extends StatefulWidget {
  const TableScrollFrame({
    super.key,
    required this.horizontalController,
    required this.verticalController,
    required this.headerHeight,
    required this.child,
  });

  static const gutterExtent = 24.0;
  final ScrollController horizontalController;
  final ScrollController verticalController;
  final double headerHeight;
  final Widget child;

  @override
  State<TableScrollFrame> createState() => _TableScrollFrameState();
}

class _TableScrollFrameState extends State<TableScrollFrame> {
  final _horizontalMetricsTarget = GlobalKey();
  final _verticalMetricsTarget = GlobalKey();

  bool _from(BuildContext? source, ScrollController controller) =>
      source != null &&
      controller.positions.length == 1 &&
      identical(Scrollable.maybeOf(source)?.position, controller.position);

  void _relay(ScrollMetrics metrics, BuildContext? source) {
    final target = _from(source, widget.horizontalController)
        ? _horizontalMetricsTarget
        : _from(source, widget.verticalController)
            ? _verticalMetricsTarget
            : null;
    final targetContext = target?.currentContext;
    if (source == null || targetContext == null) return;
    // A rail is not an ancestor of the viewport. Deliver the viewport's exact
    // metrics there, including initial layout and resize (not just scrolling).
    // Flutter still owns painting, hit testing, dragging and track paging.
    ScrollMetricsNotification(metrics: metrics, context: source)
        .dispatch(targetContext);
  }

  Widget _rail(ScrollController controller, GlobalKey metricsTarget,
      ScrollbarOrientation orientation, Color railColor, Color thumbColor) {
    return NotificationListener<ScrollMetricsNotification>(
      // Relayed notifications belong to this rail, not the page's scrollbar.
      onNotification: (_) => true,
      child: RawScrollbar(
        controller: controller,
        thumbVisibility: true,
        interactive: true,
        thickness: 10,
        crossAxisMargin: 7,
        radius: const Radius.circular(5),
        thumbColor: thumbColor,
        scrollbarOrientation: orientation,
        padding: EdgeInsets.zero,
        notificationPredicate: (notification) =>
            _from(notification.context, controller),
        child: ColoredBox(
          key: metricsTarget,
          color: railColor,
          child: const SizedBox.expand(),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final thumbColor = ScrollbarTheme.of(context).thumbColor?.resolve({}) ??
        theme.colorScheme.onSurfaceVariant.withValues(alpha: .65);
    final railColor = theme.colorScheme.surfaceContainerHighest;
    return TextFieldTapRegion(
      child: ScrollConfiguration(
        behavior: ScrollConfiguration.of(context).copyWith(scrollbars: false),
        child: Stack(
          fit: StackFit.expand,
          children: [
            Padding(
              padding: const EdgeInsets.only(
                  right: TableScrollFrame.gutterExtent,
                  bottom: TableScrollFrame.gutterExtent),
              child: ClipRect(
                child: NotificationListener<ScrollMetricsNotification>(
                  onNotification: (notification) {
                    _relay(notification.metrics, notification.context);
                    return false;
                  },
                  child: NotificationListener<ScrollNotification>(
                    onNotification: (notification) {
                      _relay(notification.metrics, notification.context);
                      return false;
                    },
                    child: widget.child,
                  ),
                ),
              ),
            ),
            Positioned(
              left: 0,
              right: TableScrollFrame.gutterExtent,
              bottom: 0,
              height: TableScrollFrame.gutterExtent,
              child: _rail(
                  widget.horizontalController,
                  _horizontalMetricsTarget,
                  ScrollbarOrientation.bottom,
                  railColor,
                  thumbColor),
            ),
            Positioned(
              top: widget.headerHeight,
              right: 0,
              bottom: TableScrollFrame.gutterExtent,
              width: TableScrollFrame.gutterExtent,
              child: _rail(widget.verticalController, _verticalMetricsTarget,
                  ScrollbarOrientation.right, railColor, thumbColor),
            ),
          ],
        ),
      ),
    );
  }
}
