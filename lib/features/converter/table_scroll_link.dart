import 'package:flutter/widgets.dart';

/// Bidirectional table-pane synchronization. Does not own the controllers.
class TableScrollLink {
  TableScrollLink(this._first, this._second) {
    _first.addListener(_fromFirst);
    _second.addListener(_fromSecond);
  }

  final ScrollController _first;
  final ScrollController _second;
  bool _syncing = false;

  void _fromFirst() => _sync(_first, _second);
  void _fromSecond() => _sync(_second, _first);

  void _sync(ScrollController source, ScrollController target) {
    if (_syncing || !source.hasClients || !target.hasClients) return;
    final offset = source.offset.clamp(0.0, target.position.maxScrollExtent);
    if ((target.offset - offset).abs() < .5) return;
    _syncing = true;
    try {
      target.jumpTo(offset);
    } finally {
      _syncing = false;
    }
  }

  void dispose() {
    _first.removeListener(_fromFirst);
    _second.removeListener(_fromSecond);
  }
}
