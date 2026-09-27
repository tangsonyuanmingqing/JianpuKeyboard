import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show ScrollCacheExtent;
import 'package:flutter/services.dart';

import '../../app/theme/app_typography.dart';
import 'table_scroll_frame.dart';
import 'smart_grid_converter.dart';
import 'smart_grid_codec.dart';
import 'smart_grid_document.dart';
import 'smart_grid_lyric_tokens.dart';
import 'smart_grid_text_field.dart';
import 'smart_grid_issue_overlay.dart';
import 'resizable_panel.dart';
import 'table_scale.dart';
import 'table_scroll_link.dart';

class SmartGridEditor extends StatefulWidget {
  final SmartGridDocument document;
  final ValueChanged<SmartGridDocument> onChanged;
  final ValueChanged<SmartGridDocument>? onViewStateChanged;
  final List<SmartGridIssue> issues;
  final ValueChanged<(int, int)>? onSelectionChanged;
  final ResizablePanelSize panelSize;
  final ValueChanged<ResizablePanelSize>? onPanelSizeChanged;
  final TableScale scale;

  const SmartGridEditor({
    super.key,
    required this.document,
    required this.onChanged,
    this.onViewStateChanged,
    this.issues = const [],
    this.onSelectionChanged,
    this.panelSize = const ResizablePanelSize(),
    this.onPanelSizeChanged,
    this.scale = const TableScale(),
  });

  @override
  State<SmartGridEditor> createState() => SmartGridEditorState();
}

class SmartGridEditorState extends State<SmartGridEditor> {
  final _horizontal = ScrollController();
  final _vertical = ScrollController();
  final _frozenVertical = ScrollController();
  final _focusNodes = <String, FocusNode>{};
  final _controllers = <String, TextEditingController>{};
  final _issuesByCell = <(int, int), SmartGridIssue>{};
  // Reuse unchanged cell subtrees instead of rebuilding every text editor
  // when only the selection or one cell changes. Bounded to the working set.
  final _cellWidgets = <String, ({Object signature, Widget child})>{};
  final _undo = <SmartGridDocument>[];
  final _redo = <SmartGridDocument>[];
  Timer? _viewportTimer;
  Timer? _cellLongPressTimer;
  int? _cellLongPressPointer;
  int? _secondaryPointer;
  void Function(Offset position)? _secondaryPointerAction;
  (int, int)? _selected;
  (int, int)? _selectionAnchor;
  (int, int)? _lastCellTap;
  DateTime? _lastCellTapAt;
  late final TableScrollLink _verticalLink;
  bool _syncingControllerValues = false;
  bool _cellCleanupScheduled = false;
  late SmartGridDocument _latestDocument;
  double _viewportWidth = 0;
  int _firstVisibleColumn = 0;
  int _lastVisibleColumn = 0;

  SmartGridDocument get _document => _latestDocument;

  double get _cellSize => widget.scale.dimension(58);
  double get _indexWidth => widget.scale.dimension(46);
  double get _typeWidth =>
      widget.scale.dimension(86).clamp(72.0, double.infinity).toDouble();
  double get _headerHeight => widget.scale.dimension(38);

  @override
  void initState() {
    super.initState();
    _indexIssues();
    _latestDocument = widget.document;
    _selected = (
      _document.selectedRow,
      _document.selectedColumn,
    );
    _selectionAnchor = _selected;
    _horizontal.addListener(_scheduleViewportSave);
    _vertical.addListener(_scheduleViewportSave);
    _verticalLink = TableScrollLink(_vertical, _frozenVertical);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (_horizontal.hasClients) {
        _horizontal.jumpTo(_document.horizontalOffset.clamp(
          0,
          _horizontal.position.maxScrollExtent,
        ));
      }
      if (_vertical.hasClients) {
        _vertical.jumpTo(_document.verticalOffset.clamp(
          0,
          _vertical.position.maxScrollExtent,
        ));
      }
    });
  }

  @override
  void didUpdateWidget(covariant SmartGridEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    _indexIssues();
    _latestDocument = widget.document;
    final documentSelection = (
      _document.selectedRow,
      _document.selectedColumn,
    );
    if (_selected != documentSelection) {
      _selected = documentSelection;
      _selectionAnchor = documentSelection;
    }
    if (oldWidget.document.rows.first.id != _document.rows.first.id) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        if (_horizontal.hasClients) {
          _horizontal.jumpTo(_document.horizontalOffset.clamp(
            0,
            _horizontal.position.maxScrollExtent,
          ));
        }
        if (_vertical.hasClients) {
          _vertical.jumpTo(_document.verticalOffset.clamp(
            0,
            _vertical.position.maxScrollExtent,
          ));
        }
      });
    }
    _syncingControllerValues = true;
    try {
      final previousRows = {
        for (final row in oldWidget.document.rows) row.id: row,
      };
      for (var row = 0; row < _document.rows.length; row++) {
        final previous = previousRows[_document.rows[row].id];
        if (identical(previous?.cells, _document.rows[row].cells)) continue;
        for (var column = 0; column < _document.columnCount; column++) {
          final key = _cellKey(row, column);
          final controller = _controllers[key];
          final value = _document.rows[row].cells[column];
          // A view-only update must not overwrite uncommitted IME text.
          if (previous != null &&
              column < previous.cells.length &&
              previous.cells[column] == value &&
              controller != null &&
              controller.value.composing.isValid &&
              !controller.value.composing.isCollapsed) {
            continue;
          }
          if (controller != null && controller.text != value) {
            controller.value = TextEditingValue(
              text: value,
              selection: TextSelection.collapsed(offset: value.length),
            );
          }
        }
      }
    } finally {
      _syncingControllerValues = false;
    }
  }

  @override
  void dispose() {
    _viewportTimer?.cancel();
    _cellLongPressTimer?.cancel();
    _verticalLink.dispose();
    _horizontal.dispose();
    _vertical.dispose();
    _frozenVertical.dispose();
    for (final node in _focusNodes.values) {
      node.dispose();
    }
    for (final controller in _controllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  void focusCell(int row, int column, {bool extendSelection = false}) {
    if (row < 0 ||
        row >= _document.rows.length ||
        column < 0 ||
        column >= _document.columnCount) {
      return;
    }
    _updateLocalSelection(row, column, extendSelection: extendSelection);
    _emitDocumentViewState(_document.copyWith(
      selectedRow: row,
      selectedColumn: column,
    ));
    _requestTextFocus(row, column);
  }

  void _applyAndFocus(
    SmartGridDocument next,
    int row,
    int column, {
    bool recordHistory = true,
    bool extendSelection = false,
  }) {
    if (row < 0 ||
        row >= next.rows.length ||
        column < 0 ||
        column >= next.columnCount) {
      return;
    }
    final selectedDocument = next.copyWith(
      selectedRow: row,
      selectedColumn: column,
    );
    if (recordHistory) {
      _undo.add(_document);
      if (_undo.length > 100) _undo.removeAt(0);
      _redo.clear();
    }
    _latestDocument = selectedDocument;
    _updateLocalSelection(row, column, extendSelection: extendSelection);
    widget.onChanged(selectedDocument);
    widget.onViewStateChanged?.call(selectedDocument);
    _requestTextFocus(row, column);
  }

  void _updateLocalSelection(
    int row,
    int column, {
    bool extendSelection = false,
  }) {
    setState(() {
      _selected = (row, column);
      if (!extendSelection || _selectionAnchor == null) {
        _selectionAnchor = (row, column);
      }
    });
    widget.onSelectionChanged?.call((row, column));
  }

  void _requestTextFocus(int row, int column) {
    _revealCell(row, column);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final key = _cellKey(row, column);
      _focusNodes.putIfAbsent(key, FocusNode.new).requestFocus();
    });
  }

  void _revealCell(int row, int column) {
    if (_horizontal.hasClients) {
      final frozenWidth = _indexWidth + _typeWidth;
      final left = frozenWidth + column * _cellSize;
      final right = left + _cellSize;
      final offset = _horizontal.offset;
      final target = left < offset + frozenWidth
          ? column * _cellSize
          : right > offset + _viewportWidth
              ? right - _viewportWidth
              : offset;
      _horizontal
          .jumpTo(target.clamp(0.0, _horizontal.position.maxScrollExtent));
    }
    if (_vertical.hasClients) {
      final top = row * _cellSize;
      final bottom = top + _cellSize;
      final offset = _vertical.offset;
      final target = top < offset
          ? top
          : bottom > offset + _vertical.position.viewportDimension
              ? bottom - _vertical.position.viewportDimension
              : offset;
      _vertical.jumpTo(target.clamp(0.0, _vertical.position.maxScrollExtent));
    }
  }

  void _apply(SmartGridDocument next, {bool recordHistory = true}) {
    if (recordHistory) {
      _undo.add(_document);
      if (_undo.length > 100) _undo.removeAt(0);
      _redo.clear();
    }
    _latestDocument = next;
    widget.onChanged(next);
  }

  void _undoOnce() {
    if (_undo.isEmpty) return;
    final previous = _undo.removeLast();
    _redo.add(_document);
    _applyAndFocus(
      previous,
      previous.selectedRow,
      previous.selectedColumn,
      recordHistory: false,
    );
  }

  void _redoOnce() {
    if (_redo.isEmpty) return;
    final next = _redo.removeLast();
    _undo.add(_document);
    _applyAndFocus(
      next,
      next.selectedRow,
      next.selectedColumn,
      recordHistory: false,
    );
  }

  @override
  Widget build(BuildContext context) {
    return CallbackShortcuts(
      bindings: <ShortcutActivator, VoidCallback>{
        const SingleActivator(LogicalKeyboardKey.keyZ, control: true):
            _undoOnce,
        const SingleActivator(LogicalKeyboardKey.keyY, control: true):
            _redoOnce,
        const SingleActivator(LogicalKeyboardKey.keyC, control: true):
            _copySelectedCell,
        const SingleActivator(LogicalKeyboardKey.keyX, control: true):
            _cutSelectedCell,
        const SingleActivator(LogicalKeyboardKey.keyV, control: true): () {
          _pasteMatrix();
        },
        const SingleActivator(LogicalKeyboardKey.keyA, control: true):
            _selectAll,
        const SingleActivator(LogicalKeyboardKey.delete): _clearSelectedCell,
        const SingleActivator(LogicalKeyboardKey.arrowLeft): () => _move(0, -1),
        const SingleActivator(LogicalKeyboardKey.arrowRight): () => _move(0, 1),
        const SingleActivator(LogicalKeyboardKey.arrowUp): () => _move(-1, 0),
        const SingleActivator(LogicalKeyboardKey.arrowDown): () => _move(1, 0),
        const SingleActivator(LogicalKeyboardKey.arrowLeft, shift: true): () =>
            _move(0, -1, extendSelection: true),
        const SingleActivator(LogicalKeyboardKey.arrowRight, shift: true): () =>
            _move(0, 1, extendSelection: true),
        const SingleActivator(LogicalKeyboardKey.arrowUp, shift: true): () =>
            _move(-1, 0, extendSelection: true),
        const SingleActivator(LogicalKeyboardKey.arrowDown, shift: true): () =>
            _move(1, 0, extendSelection: true),
        const SingleActivator(LogicalKeyboardKey.tab): () => _move(0, 1),
        const SingleActivator(LogicalKeyboardKey.tab, shift: true): () =>
            _move(0, -1),
        const SingleActivator(LogicalKeyboardKey.enter): () => _move(1, 0),
        const SingleActivator(LogicalKeyboardKey.equal, control: true): () {
          unawaited(_showCellOperationMenu(insertOnly: true));
        },
        const SingleActivator(LogicalKeyboardKey.equal,
            control: true, shift: true): () {
          unawaited(_showCellOperationMenu(insertOnly: true));
        },
        const SingleActivator(LogicalKeyboardKey.minus, control: true): () {
          unawaited(_showCellOperationMenu(deleteOnly: true));
        },
      },
      child: Focus(
        autofocus: true,
        child:
            Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Wrap(spacing: 8, runSpacing: 8, children: [
            OutlinedButton.icon(
              key: const Key('grid-add-row'),
              onPressed: () => _apply(_document.addRow()),
              icon: const Icon(Icons.add),
              label: const Text('添加行'),
            ),
            OutlinedButton.icon(
              key: const Key('grid-add-column'),
              onPressed: () => _apply(_document.addColumn()),
              icon: const Icon(Icons.view_column),
              label: const Text('添加列'),
            ),
            OutlinedButton.icon(
              key: const Key('grid-cell-actions'),
              onPressed: _hasSingleCellSelection
                  ? () => unawaited(_showCellOperationMenu())
                  : null,
              icon: const Icon(Icons.swap_horiz),
              label: const Text('单元格操作'),
            ),
            OutlinedButton.icon(
              key: const Key('grid-paste'),
              onPressed: _pasteMatrix,
              icon: const Icon(Icons.content_paste),
              label: const Text('粘贴表格'),
            ),
            IconButton(
              tooltip: '撤销',
              onPressed: _undo.isEmpty ? null : _undoOnce,
              icon: const Icon(Icons.undo),
            ),
            IconButton(
              tooltip: '重做',
              onPressed: _redo.isEmpty ? null : _redoOnce,
              icon: const Icon(Icons.redo),
            ),
          ]),
          const SizedBox(height: 8),
          ResizablePanel(
            panelId: 'smart-grid',
            size: widget.panelSize,
            onSizeChanged: widget.onPanelSizeChanged ?? (_) {},
            child: Container(
              decoration: BoxDecoration(
                border: Border.all(
                    color: Theme.of(context).colorScheme.outlineVariant),
                borderRadius: BorderRadius.circular(8),
              ),
              child: TableScrollFrame(
                horizontalController: _horizontal,
                verticalController: _vertical,
                headerHeight: _headerHeight,
                child: LayoutBuilder(builder: (context, constraints) {
                  _viewportWidth = constraints.maxWidth;
                  final header = _header(context);
                  return AnimatedBuilder(
                    animation: _horizontal,
                    child: _frozenPane(context),
                    builder: (context, frozenPane) {
                      final offset = _horizontal.hasClients
                          ? _horizontal.offset
                          : _document.horizontalOffset;
                      // Include one overscan column at each edge. Keep the
                      // full scroll extent with spacers, not hidden fields.
                      _firstVisibleColumn = (offset / _cellSize)
                          .floor()
                          .clamp(0, _document.columnCount - 1);
                      _firstVisibleColumn = (_firstVisibleColumn - 1)
                          .clamp(0, _document.columnCount - 1);
                      _lastVisibleColumn = ((offset +
                                  _viewportWidth -
                                  _indexWidth -
                                  _typeWidth) /
                              _cellSize)
                          .ceil()
                          .clamp(0, _document.columnCount - 1);
                      return Stack(
                        children: [
                          SingleChildScrollView(
                            controller: _horizontal,
                            scrollDirection: Axis.horizontal,
                            child: SizedBox(
                              width: _indexWidth +
                                  _typeWidth +
                                  _document.columnCount * _cellSize,
                              child: Column(children: [
                                header,
                                Expanded(
                                  child: ReorderableListView.builder(
                                    scrollController: _vertical,
                                    // Avoid rebuilding offscreen editors
                                    // whenever visible columns change.
                                    scrollCacheExtent:
                                        const ScrollCacheExtent.pixels(0),
                                    buildDefaultDragHandles: false,
                                    itemCount: _document.rows.length,
                                    itemBuilder: (context, row) => KeyedSubtree(
                                      key: ValueKey(_document.rows[row].id),
                                      child: _row(context, row),
                                    ),
                                    onReorderItem: (oldIndex, newIndex) =>
                                        _apply(_document.reorderGroup(
                                            oldIndex, newIndex)),
                                  ),
                                ),
                              ]),
                            ),
                          ),
                          Positioned(
                            left: 0,
                            top: 0,
                            bottom: 0,
                            width: _indexWidth + _typeWidth,
                            child: NotificationListener<ScrollNotification>(
                              onNotification: (_) => true,
                              child: frozenPane!,
                            ),
                          ),
                        ],
                      );
                    },
                  );
                }),
              ),
            ),
          ),
          const SizedBox(height: 6),
          const Text(
              '提示：Enter 向下、Tab 向右；可粘贴由制表符和换行组成的表格。右键单击或左键长按格子、行号、列标题可打开操作菜单，Ctrl + 加号／减号可打开插入／删除菜单。'),
        ]),
      ),
    );
  }

  Widget _header(BuildContext context) {
    final color = Theme.of(context).colorScheme.surfaceContainerHighest;
    return SizedBox(
      height: _headerHeight,
      child: Row(children: [
        _headerCell('#', _indexWidth, color),
        _headerCell('类型', _typeWidth, color),
        for (var column = 0; column < _document.columnCount; column++)
          Listener(
            key: ValueKey('grid-column-header-$column'),
            behavior: HitTestBehavior.translucent,
            onPointerDown: (event) => _trackSecondaryPointer(
              event,
              (position) => unawaited(_showColumnContextMenu(column, position)),
            ),
            onPointerUp: _openSecondaryPointerMenu,
            onPointerCancel: _cancelSecondaryPointer,
            child: GestureDetector(
              behavior: HitTestBehavior.translucent,
              onLongPressStart: (details) => unawaited(
                  _showColumnContextMenu(column, details.globalPosition)),
              child: InkWell(
                child:
                    _headerCell(smartGridColumnLabel(column), _cellSize, color),
              ),
            ),
          ),
      ]),
    );
  }

  Widget _frozenPane(BuildContext context) {
    final headerColor = Theme.of(context).colorScheme.surfaceContainerHighest;
    return ColoredBox(
      color: Theme.of(context).colorScheme.surface,
      child: Column(children: [
        SizedBox(
          height: _headerHeight,
          child: Row(children: [
            _headerCell('#', _indexWidth, headerColor),
            _headerCell('类型', _typeWidth, headerColor),
          ]),
        ),
        Expanded(
          child: ReorderableListView.builder(
            scrollController: _frozenVertical,
            scrollCacheExtent: const ScrollCacheExtent.pixels(0),
            buildDefaultDragHandles: false,
            itemCount: _document.rows.length,
            itemBuilder: (context, row) => KeyedSubtree(
              key: ValueKey('frozen-${_document.rows[row].id}'),
              child: _frozenRow(context, row),
            ),
            onReorderItem: (oldIndex, newIndex) => _apply(
              _document.reorderGroup(oldIndex, newIndex),
            ),
          ),
        ),
      ]),
    );
  }

  Widget _frozenRow(BuildContext context, int rowIndex) {
    final row = _document.rows[rowIndex];
    final groupNumber = _groupNumberFor(row.groupId);
    final tint = groupNumber.isEven
        ? Theme.of(context)
            .colorScheme
            .secondaryContainer
            .withValues(alpha: .22)
        : Theme.of(context).colorScheme.primaryContainer.withValues(alpha: .18);
    return SizedBox(
      height: _cellSize,
      child: ColoredBox(
        color: tint,
        child: Row(children: [
          Tooltip(
            message:
                '第 ${rowIndex + 1} 行 · 第 ${groupNumber < 1 ? '?' : groupNumber} 组',
            child: ReorderableDragStartListener(
              index: rowIndex,
              child: Listener(
                key: ValueKey('grid-row-header-$rowIndex'),
                behavior: HitTestBehavior.translucent,
                onPointerDown: (event) => _trackSecondaryPointer(
                  event,
                  (position) =>
                      unawaited(_showRowContextMenu(rowIndex, position)),
                ),
                onPointerUp: _openSecondaryPointerMenu,
                onPointerCancel: _cancelSecondaryPointer,
                child: GestureDetector(
                  behavior: HitTestBehavior.translucent,
                  onLongPressStart: (details) => unawaited(
                    _showRowContextMenu(rowIndex, details.globalPosition),
                  ),
                  child: InkWell(
                    child: _headerCell('${rowIndex + 1}', _indexWidth, tint),
                  ),
                ),
              ),
            ),
          ),
          SizedBox(
            width: _typeWidth,
            child: Padding(
              padding: EdgeInsets.all(widget.scale.dimension(4)),
              child: DropdownButtonFormField<SmartGridRowType>(
                initialValue: row.type,
                isDense: true,
                isExpanded: true,
                decoration: InputDecoration(
                  border: const OutlineInputBorder(),
                  contentPadding: EdgeInsets.symmetric(
                    horizontal: widget.scale.dimension(2),
                    vertical: widget.scale.dimension(4),
                  ),
                ).copyWith(
                  labelText: groupNumber < 1 ? null : '第 $groupNumber 组',
                ),
                items: const [
                  DropdownMenuItem(
                      value: SmartGridRowType.score, child: Text('谱')),
                  DropdownMenuItem(
                      value: SmartGridRowType.lyrics, child: Text('词')),
                ],
                onChanged: (value) {
                  if (value != null) {
                    _apply(_document.setRowType(rowIndex, value));
                  }
                },
              ),
            ),
          ),
        ]),
      ),
    );
  }

  Widget _row(BuildContext context, int rowIndex) {
    final row = _document.rows[rowIndex];
    final groupNumber = _groupNumberFor(row.groupId);
    final tint = groupNumber.isEven
        ? Theme.of(context)
            .colorScheme
            .secondaryContainer
            .withValues(alpha: .22)
        : Theme.of(context).colorScheme.primaryContainer.withValues(alpha: .18);
    final columns = _visibleColumnIndexes(rowIndex);
    final issues = [
      for (final column in columns)
        if (_issuesByCell[(rowIndex, column)] case final SmartGridIssue issue)
          issue,
    ];
    final child = SizedBox(
      height: _cellSize,
      child: ColoredBox(
        color: tint,
        child: Row(children: [
          // The frozen pane owns these controls; the scrolling body only
          // reserves their width instead of laying out hidden duplicates.
          SizedBox(width: _indexWidth + _typeWidth),
          ..._visibleCells(context, rowIndex, columns),
        ]),
      ),
    );
    return SmartGridIssueOverlay(
      key: ValueKey('grid-issues-${_document.rows[rowIndex].id}'),
      issues: issues,
      leadingWidth: _indexWidth + _typeWidth,
      scale: widget.scale,
      child: child,
    );
  }

  List<int> _visibleColumnIndexes(int row) => (<int>{
        for (var column = _firstVisibleColumn;
            column <= _lastVisibleColumn;
            column++)
          column,
        // Do not dispose an active editor (including an IME composition) merely
        // because the user scrolls horizontally. Also allow deferred focus.
        if (_selected?.$1 == row) _selected!.$2,
      }.toList()
        ..sort());

  List<Widget> _visibleCells(BuildContext context, int row, List<int> columns) {
    final children = <Widget>[];
    var nextColumn = 0;
    for (final column in columns) {
      if (column < 0 || column >= _document.columnCount) continue;
      if (column > nextColumn) {
        children.add(SizedBox(width: (column - nextColumn) * _cellSize));
      }
      children.add(_editableCell(context, row, column));
      nextColumn = column + 1;
    }
    if (nextColumn < _document.columnCount) {
      children.add(
          SizedBox(width: (_document.columnCount - nextColumn) * _cellSize));
    }
    return children;
  }

  void _indexIssues() {
    _issuesByCell.clear();
    for (final issue in widget.issues) {
      // Preserve the existing first-issue priority if a cell has several.
      _issuesByCell.putIfAbsent((issue.row, issue.column), () => issue);
    }
  }

  Widget _editableCell(BuildContext context, int row, int column) {
    _scheduleInactiveCellCleanup();
    final value = _document.rows[row].cells[column];
    final clipped = _isVisuallyClipped(value);
    final issue = _issuesByCell[(row, column)];
    final selected = _isCellSelected(row, column);
    final key = _cellKey(row, column);
    final signature = (
      row,
      value,
      selected,
      widget.scale.percent,
      Theme.of(context),
      issue?.message,
      issue?.severity,
    );
    final cached = _cellWidgets.remove(key);
    if (cached != null && cached.signature == signature) {
      _cellWidgets[key] = cached;
      return cached.child;
    }
    final borderColor = issue?.severity == SmartGridIssueSeverity.error
        ? Theme.of(context).colorScheme.error
        : issue != null
            ? Colors.amber.shade800
            : selected
                ? Theme.of(context).colorScheme.primary
                : Theme.of(context).colorScheme.outlineVariant;
    final focusNode = _focusNodes.putIfAbsent(key, FocusNode.new);
    final controller = _controllers.putIfAbsent(
      key,
      () {
        final rowId = _document.rows[row].id;
        final next = TextEditingController(text: value);
        next.addListener(() {
          final currentRow =
              _document.rows.indexWhere((item) => item.id == rowId);
          if (currentRow < 0 || column >= _document.columnCount) return;
          _handleCellControllerChanged(currentRow, column, next);
        });
        return next;
      },
    );
    final child = Listener(
      key: ValueKey('grid-cell-container-$key'),
      behavior: HitTestBehavior.translucent,
      onPointerDown: (event) {
        _handleCellPointerDown(event, row, column);
      },
      onPointerUp: _handleCellPointerUp,
      onPointerCancel: _handleCellPointerCancel,
      child: Tooltip(
        message: issue?.message ??
            (clipped && value.isNotEmpty
                ? value
                : '${smartGridColumnLabel(column)}${row + 1}'),
        child: Container(
          width: _cellSize,
          height: _cellSize,
          decoration: BoxDecoration(
              border: Border.all(
                  color: borderColor,
                  width: issue != null || selected ? 2 : 1)),
          padding: EdgeInsets.all(widget.scale.dimension(3)),
          child: Stack(
            children: [
              Positioned.fill(
                child: SmartGridTextField(
                  key: ValueKey('grid-cell-$key'),
                  focusNode: focusNode,
                  controller: controller,
                  style: AppTypography.of(context).gridCellAt(
                    widget.scale.font(value.length > 4 ? 11 : 16),
                  ),
                  onTap: () => _selectCell(row, column),
                  onSubmitted: (_) => focusCell(
                      (row + 1).clamp(0, _document.rows.length - 1), column),
                ),
              ),
              if (issue == null && clipped && value.isNotEmpty)
                Positioned(
                  right: 2,
                  top: 2,
                  child: IgnorePointer(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.primary,
                        shape: BoxShape.circle,
                      ),
                      child: SizedBox(
                        width: widget.scale.dimension(5),
                        height: widget.scale.dimension(5),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
    _cellWidgets[key] = (signature: signature, child: child);
    if (_cellWidgets.length > 4096) {
      _cellWidgets.remove(_cellWidgets.keys.first);
    }
    return child;
  }

  void _scheduleInactiveCellCleanup() {
    if (_cellCleanupScheduled) return;
    _cellCleanupScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _cellCleanupScheduled = false;
      if (!mounted) return;
      final selected = _selected;
      final selectedKey =
          selected != null && selected.$1 < _document.rows.length
              ? _cellKey(selected.$1, selected.$2)
              : null;
      // Wait until removed EditableText/Focus elements have detached. Their
      // values live in the document, so offscreen editors can be recreated.
      final inactive = _focusNodes.entries
          .where((entry) =>
              entry.key != selectedKey &&
              !entry.value.hasFocus &&
              entry.value.context?.mounted != true)
          .map((entry) => entry.key)
          .toList();
      for (final key in inactive) {
        _cellWidgets.remove(key);
        _controllers.remove(key)?.dispose();
        _focusNodes.remove(key)?.dispose();
      }
    });
  }

  void _selectCell(int row, int column) {
    focusCell(row, column);
  }

  void _handleCellPointerDown(PointerDownEvent event, int row, int column) {
    _trackSecondaryPointer(
      event,
      (position) => _openCellOperationMenuFor(
        row,
        column,
        position: position,
      ),
    );
    _startCellLongPress(event, row, column);
    if ((event.buttons & kPrimaryButton) == 0 ||
        _document.rows[row].type != SmartGridRowType.score) {
      return;
    }

    final now = DateTime.now();
    final doubleTapped = _lastCellTap == (row, column) &&
        _lastCellTapAt != null &&
        now.difference(_lastCellTapAt!) <= const Duration(milliseconds: 500);
    _lastCellTap = (row, column);
    _lastCellTapAt = now;
    if (!doubleTapped) return;

    _lastCellTap = null;
    _lastCellTapAt = null;
    unawaited(_showScorePicker(
      row,
      column,
      event.position,
    ));
  }

  void _handleCellControllerChanged(
    int row,
    int column,
    TextEditingController controller,
  ) {
    if (_syncingControllerValues) return;
    final value = controller.text;
    if (_document.rows[row].cells[column] == value) return;
    final composing = controller.value.composing;
    if (composing.isValid && !composing.isCollapsed) return;
    if (_document.rows[row].type != SmartGridRowType.lyrics) {
      _apply(_document.setCell(row, column, value));
      return;
    }

    final pieces = splitSmartGridLyricCells(value);
    if (pieces.length > 1) {
      final write = _document.overwriteCells(
        row,
        column,
        pieces,
        keepTrailingCell: true,
      );
      if (write.omittedCount > 0) {
        _showMessage('已达到表格最大列数，剩余 ${write.omittedCount} 项歌词未写入。');
      }
      final nextColumn = (column + write.writtenCount)
          .clamp(0, write.document.columnCount - 1);
      _applyAndFocus(write.document, row, nextColumn);
      return;
    }

    final next = _document.setCell(row, column, value);
    if (isSingleSmartGridCjk(value)) {
      _applyAndFocus(
        next,
        row,
        (column + 1).clamp(0, next.columnCount - 1),
      );
      return;
    }
    _apply(next);
  }

  Future<void> _showScorePicker(int row, int column, Offset position) async {
    final result = await showMenu<_ScorePickerResult>(
      context: context,
      position: _contextMenuPosition(position),
      items: [
        const PopupMenuItem<_ScorePickerResult>(
          enabled: false,
          padding: EdgeInsets.zero,
          child: _ScoreCellPicker(),
        ),
      ],
    );
    if (result == null || !mounted) return;
    if (result.clear) {
      _applyAndFocus(_document.setCell(row, column, ''), row, column);
      return;
    }

    var next = _document.setCell(row, column, result.value!);
    if (column == next.columnCount - 1 &&
        next.columnCount < SmartGridDocument.maxColumns) {
      next = next.addColumn();
    }
    if (column == next.columnCount - 1) _showMessage('已达到表格最大列数。');
    _applyAndFocus(
      next,
      row,
      (column + 1).clamp(0, next.columnCount - 1),
    );
  }

  bool _isVisuallyClipped(String value) {
    if (value.isEmpty) return false;
    final averageCharacterWidth = widget.scale.font(16) * .85;
    return value.runes.length * averageCharacterWidth >
        _cellSize - widget.scale.dimension(8);
  }

  void _startCellLongPress(PointerDownEvent event, int row, int column) {
    if ((event.buttons & kPrimaryButton) == 0) return;
    _cellLongPressTimer?.cancel();
    _cellLongPressPointer = event.pointer;
    _cellLongPressTimer = Timer(const Duration(milliseconds: 500), () {
      if (!mounted || _cellLongPressPointer != event.pointer) return;
      _cellLongPressPointer = null;
      _openCellOperationMenuFor(row, column, position: event.position);
    });
  }

  void _stopCellLongPress(PointerEvent event) {
    if (_cellLongPressPointer != event.pointer) return;
    _cellLongPressTimer?.cancel();
    _cellLongPressPointer = null;
  }

  void _handleCellPointerUp(PointerUpEvent event) {
    _openSecondaryPointerMenu(event);
    _stopCellLongPress(event);
  }

  void _handleCellPointerCancel(PointerCancelEvent event) {
    _cancelSecondaryPointer(event);
    _stopCellLongPress(event);
  }

  void _trackSecondaryPointer(
    PointerDownEvent event,
    void Function(Offset position) action,
  ) {
    if ((event.buttons & kSecondaryButton) == 0) return;
    _cellLongPressTimer?.cancel();
    _cellLongPressPointer = null;
    _secondaryPointer = event.pointer;
    _secondaryPointerAction = action;
  }

  void _openSecondaryPointerMenu(PointerUpEvent event) {
    if (_secondaryPointer != event.pointer) return;
    final action = _secondaryPointerAction;
    _secondaryPointer = null;
    _secondaryPointerAction = null;
    if (action != null && mounted) action(event.position);
  }

  void _cancelSecondaryPointer(PointerEvent event) {
    if (_secondaryPointer != event.pointer) return;
    _secondaryPointer = null;
    _secondaryPointerAction = null;
  }

  Future<void> _showRowContextMenu(int row, Offset position) async {
    final action = await showMenu<String>(
      context: context,
      position: _contextMenuPosition(position),
      items: [
        _contextMenuItem('score-above', Icons.vertical_align_top, '在上方插入谱行'),
        _contextMenuItem('lyrics-above', Icons.vertical_align_top, '在上方插入词行'),
        _contextMenuItem('score-below', Icons.vertical_align_bottom, '在下方插入谱行'),
        _contextMenuItem('lyrics-below', Icons.lyrics_outlined, '在下方插入词行'),
        _contextMenuItem('delete', Icons.delete_outline, '删除此行'),
        _contextMenuItem('clear', Icons.clear_all, '清空此行'),
      ],
    );
    if (!mounted) return;
    _applyRowMenuAction(row, action);
  }

  void _applyRowMenuAction(int row, String? action) {
    if (action == 'score-above') {
      _apply(_document.insertRow(row, SmartGridRowType.score));
    }
    if (action == 'lyrics-above') {
      _apply(_document.insertRow(row, SmartGridRowType.lyrics));
    }
    if (action == 'score-below') {
      _apply(_document.insertRow(row + 1, SmartGridRowType.score));
    }
    if (action == 'lyrics-below') {
      _apply(_document.insertRow(row + 1, SmartGridRowType.lyrics));
    }
    if (action == 'delete') _apply(_document.deleteRow(row));
    if (action == 'clear') {
      var next = _document;
      for (var column = 0; column < next.columnCount; column++) {
        next = next.setCell(row, column, '');
      }
      _apply(next);
    }
  }

  Future<void> _showColumnContextMenu(int column, Offset position) async {
    final action = await showMenu<String>(
      context: context,
      position: _contextMenuPosition(position),
      items: [
        _contextMenuItem('insert-left', Icons.keyboard_arrow_left, '在左侧插入一列'),
        _contextMenuItem('insert-right', Icons.keyboard_arrow_right, '在右侧插入一列'),
        _contextMenuItem('delete', Icons.delete_outline, '删除此列'),
        _contextMenuItem('clear', Icons.clear_all, '清空此列'),
      ],
    );
    if (!mounted) return;
    _applyColumnMenuAction(column, action);
  }

  void _applyColumnMenuAction(int column, String? action) {
    if (action == 'insert-left') {
      _apply(_document.insertColumn(column));
    }
    if (action == 'insert-right') {
      _apply(_document.insertColumn(column + 1));
    }
    if (action == 'delete') {
      _apply(_document.deleteColumn(column));
    }
    if (action == 'clear') {
      var next = _document;
      for (var row = 0; row < next.rows.length; row++) {
        next = next.setCell(row, column, '');
      }
      _apply(next);
    }
  }

  bool get _hasSingleCellSelection =>
      _selected != null && _selected == _selectionAnchor;

  void _openCellOperationMenuFor(
    int row,
    int column, {
    Offset? position,
  }) {
    focusCell(row, column);
    if (position == null) {
      unawaited(_showCellOperationMenu());
      return;
    }
    unawaited(_showCellContextMenu(position));
  }

  Future<void> _showCellOperationMenu({
    bool insertOnly = false,
    bool deleteOnly = false,
  }) async {
    if (!_hasSingleCellSelection) {
      _showMessage('请先单击选择一个格子后再操作。');
      return;
    }
    final action = await showModalBottomSheet<SmartGridCellOperation>(
      context: context,
      builder: (context) => SafeArea(
        child: Wrap(
          children: [
            if (!deleteOnly) ...[
              ListTile(
                leading: const Icon(Icons.keyboard_arrow_right),
                title: const Text('插入空格，本行向右移动'),
                onTap: () => Navigator.pop(
                  context,
                  SmartGridCellOperation.insertRowRight,
                ),
              ),
              ListTile(
                leading: const Icon(Icons.keyboard_arrow_down),
                title: const Text('插入空格，本列相同类型行向下移动'),
                onTap: () => Navigator.pop(
                  context,
                  SmartGridCellOperation.insertSameTypeDown,
                ),
              ),
              ListTile(
                leading: const Icon(Icons.south),
                title: const Text('插入空格，本列所有行向下移动'),
                onTap: () => Navigator.pop(
                  context,
                  SmartGridCellOperation.insertAllRowsDown,
                ),
              ),
            ],
            if (!insertOnly) ...[
              ListTile(
                leading: const Icon(Icons.keyboard_arrow_left),
                title: const Text('删除格子，本行向左移动'),
                onTap: () => Navigator.pop(
                  context,
                  SmartGridCellOperation.deleteRowLeft,
                ),
              ),
              ListTile(
                leading: const Icon(Icons.keyboard_arrow_up),
                title: const Text('删除格子，本列相同类型行向上移动'),
                onTap: () => Navigator.pop(
                  context,
                  SmartGridCellOperation.deleteSameTypeUp,
                ),
              ),
              ListTile(
                leading: const Icon(Icons.north),
                title: const Text('删除格子，本列所有行向上移动'),
                onTap: () => Navigator.pop(
                  context,
                  SmartGridCellOperation.deleteAllRowsUp,
                ),
              ),
            ],
          ],
        ),
      ),
    );
    if (action == null || !mounted) return;
    await _applyCellOperation(action);
  }

  Future<void> _showCellContextMenu(Offset position) async {
    if (!_hasSingleCellSelection) {
      _showMessage('请先单击选择一个格子后再操作。');
      return;
    }
    final action = await showMenu<SmartGridCellOperation>(
      context: context,
      position: _contextMenuPosition(position),
      items: [
        _contextMenuItem(
          SmartGridCellOperation.insertRowRight,
          Icons.keyboard_arrow_right,
          '插入空格，本行向右移动',
        ),
        _contextMenuItem(
          SmartGridCellOperation.insertSameTypeDown,
          Icons.keyboard_arrow_down,
          '插入空格，本列相同类型行向下移动',
        ),
        _contextMenuItem(
          SmartGridCellOperation.insertAllRowsDown,
          Icons.south,
          '插入空格，本列所有行向下移动',
        ),
        _contextMenuItem(
          SmartGridCellOperation.deleteRowLeft,
          Icons.keyboard_arrow_left,
          '删除格子，本行向左移动',
        ),
        _contextMenuItem(
          SmartGridCellOperation.deleteSameTypeUp,
          Icons.keyboard_arrow_up,
          '删除格子，本列相同类型行向上移动',
        ),
        _contextMenuItem(
          SmartGridCellOperation.deleteAllRowsUp,
          Icons.north,
          '删除格子，本列所有行向上移动',
        ),
      ],
    );
    if (action == null || !mounted) return;
    await _applyCellOperation(action);
  }

  RelativeRect _contextMenuPosition(Offset globalPosition) {
    final overlay =
        Overlay.of(context).context.findRenderObject()! as RenderBox;
    final localPosition = overlay.globalToLocal(globalPosition);
    final left = localPosition.dx.clamp(0.0, overlay.size.width).toDouble();
    final top = localPosition.dy.clamp(0.0, overlay.size.height).toDouble();
    return RelativeRect.fromLTRB(
      left,
      top,
      overlay.size.width - left,
      overlay.size.height - top,
    );
  }

  PopupMenuItem<T> _contextMenuItem<T>(T value, IconData icon, String label) =>
      PopupMenuItem<T>(
        value: value,
        child: _contextMenuItemContent(icon, label),
      );

  Widget _contextMenuItemContent(IconData icon, String label) => ConstrainedBox(
        constraints: const BoxConstraints(minWidth: 260, maxWidth: 360),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 20),
          const SizedBox(width: 12),
          Flexible(child: Text(label)),
        ]),
      );

  Future<void> _applyCellOperation(SmartGridCellOperation operation) async {
    final selected = _selected;
    if (selected == null || !_hasSingleCellSelection) {
      _showMessage('单元格操作仅支持单个格子。');
      return;
    }
    if (operation.movesAllRowTypes &&
        _wouldCreateCellTypeError(selected.$1, selected.$2, operation)) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('内容可能进入不匹配的行'),
          content: const Text('继续后，数字音符或歌词可能进入另一种类型的行，并显示为格式错误。是否继续？'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('继续移动'),
            ),
          ],
        ),
      );
      if (confirmed != true || !mounted) return;
    }
    final next = _document.applyCellOperation(
      selected.$1,
      selected.$2,
      operation,
    );
    if (next == null) {
      _showMessage(
          operation.inserts ? '已达到表格最大行列数，无法在保留内容的情况下插入。' : '无法执行单元格操作。');
      return;
    }
    setState(() => _selectionAnchor = selected);
    _apply(next);
  }

  bool _wouldCreateCellTypeError(
    int row,
    int column,
    SmartGridCellOperation operation,
  ) {
    if (operation == SmartGridCellOperation.insertAllRowsDown) {
      for (var source = row; source < _document.rows.length; source++) {
        final value = _document.rows[source].cells[column];
        final targetType = source + 1 < _document.rows.length
            ? _document.rows[source + 1].type
            : _document.rows.last.type;
        if (_isInvalidAfterRowMove(
          _document.rows[source].type,
          targetType,
          value,
        )) {
          return true;
        }
      }
    }
    if (operation == SmartGridCellOperation.deleteAllRowsUp) {
      for (var source = row + 1; source < _document.rows.length; source++) {
        final value = _document.rows[source].cells[column];
        final targetType = _document.rows[source - 1].type;
        if (_isInvalidAfterRowMove(
          _document.rows[source].type,
          targetType,
          value,
        )) {
          return true;
        }
      }
    }
    return false;
  }

  bool _isInvalidAfterRowMove(
    SmartGridRowType sourceType,
    SmartGridRowType targetType,
    String value,
  ) {
    if (value.isEmpty) return false;
    if (validateSmartGridCell(targetType, value) != null) return true;
    return sourceType == SmartGridRowType.score &&
        targetType == SmartGridRowType.lyrics &&
        RegExp(r"^(?:[1-7][,']?|0)$").hasMatch(value);
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  void _move(int rowDelta, int columnDelta, {bool extendSelection = false}) {
    final selected = _selected;
    if (selected == null) return;
    focusCell(
      (selected.$1 + rowDelta).clamp(0, _document.rows.length - 1),
      (selected.$2 + columnDelta).clamp(0, _document.columnCount - 1),
      extendSelection: extendSelection,
    );
  }

  void _copySelectedCell() {
    final bounds = _selectionBounds();
    if (bounds == null) return;
    final rows = <String>[];
    for (var row = bounds.$1; row <= bounds.$2; row++) {
      rows.add(_document.rows[row].cells
          .sublist(bounds.$3, bounds.$4 + 1)
          .join('\t'));
    }
    Clipboard.setData(ClipboardData(text: rows.join('\n')));
  }

  void _cutSelectedCell() {
    _copySelectedCell();
    _clearSelectedCell();
  }

  void _clearSelectedCell() {
    final bounds = _selectionBounds();
    if (bounds == null) return;
    var next = _document;
    for (var row = bounds.$1; row <= bounds.$2; row++) {
      for (var column = bounds.$3; column <= bounds.$4; column++) {
        next = next.setCell(row, column, '');
      }
    }
    _apply(next);
  }

  void _selectAll() {
    final selectedRow = _document.rows.length - 1;
    final selectedColumn = _document.columnCount - 1;
    setState(() {
      _selectionAnchor = (0, 0);
      _selected = (selectedRow, selectedColumn);
    });
    widget.onSelectionChanged?.call((selectedRow, selectedColumn));
    _emitDocumentViewState(_document.copyWith(
      selectedRow: selectedRow,
      selectedColumn: selectedColumn,
    ));
    _requestTextFocus(selectedRow, selectedColumn);
  }

  bool _isCellSelected(int row, int column) {
    final bounds = _selectionBounds();
    return bounds != null &&
        row >= bounds.$1 &&
        row <= bounds.$2 &&
        column >= bounds.$3 &&
        column <= bounds.$4;
  }

  (int, int, int, int)? _selectionBounds() {
    final anchor = _selectionAnchor;
    final selected = _selected;
    if (anchor == null || selected == null) return null;
    return (
      anchor.$1 < selected.$1 ? anchor.$1 : selected.$1,
      anchor.$1 > selected.$1 ? anchor.$1 : selected.$1,
      anchor.$2 < selected.$2 ? anchor.$2 : selected.$2,
      anchor.$2 > selected.$2 ? anchor.$2 : selected.$2,
    );
  }

  Future<void> _pasteMatrix() async {
    final selected = _selected;
    if (selected == null) return;
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final text = data?.text;
    if (!mounted || text == null || text.isEmpty) return;
    final lines =
        text.replaceAll('\r\n', '\n').replaceAll('\r', '\n').split('\n');
    var next = _document.ensureSize(
      selected.$1 + lines.length,
      _document.columnCount,
    );
    final matrix = <List<String>>[];
    for (var row = 0; row < lines.length; row++) {
      final targetRow = selected.$1 + row;
      if (targetRow >= next.rows.length) break;
      matrix.add(_pastedCells(lines[row], next.rows[targetRow].type));
    }
    final neededColumns = matrix.fold<int>(
      0,
      (width, row) => row.length > width ? row.length : width,
    );
    next = next.ensureSize(
      selected.$1 + matrix.length,
      selected.$2 + neededColumns,
    );
    for (var row = 0; row < matrix.length; row++) {
      final targetRow = selected.$1 + row;
      if (targetRow >= next.rows.length) break;
      for (var column = 0; column < matrix[row].length; column++) {
        final targetColumn = selected.$2 + column;
        if (targetColumn >= next.columnCount) break;
        next = next.setCell(targetRow, targetColumn, matrix[row][column]);
      }
    }
    final lastRow =
        (selected.$1 + matrix.length - 1).clamp(0, next.rows.length - 1);
    final lastColumn =
        (selected.$2 + neededColumns - 1).clamp(0, next.columnCount - 1);
    _applyAndFocus(next, lastRow, lastColumn);
  }

  List<String> _pastedCells(String line, SmartGridRowType type) {
    final chunks = line.contains('\t')
        ? line.split('\t')
        : line.trim().split(RegExp(r'\s+'));
    if (type != SmartGridRowType.lyrics) {
      return chunks.map((value) => value == '_' ? '' : value).toList();
    }
    return [
      for (final chunk in chunks)
        if (chunk == '_')
          ''
        else if (splitSmartGridLyricCells(chunk).isEmpty)
          ''
        else
          ...splitSmartGridLyricCells(chunk),
    ];
  }

  Widget _headerCell(String text, double width, Color color) => Container(
        width: width,
        alignment: Alignment.center,
        decoration: BoxDecoration(
            color: color,
            border: Border.all(
                color: Theme.of(context).colorScheme.outlineVariant)),
        child: Text(text, style: AppTypography.of(context).gridHeader),
      );

  String _cellKey(int row, int column) => '${_document.rows[row].id}:$column';

  void _scheduleViewportSave() {
    _viewportTimer?.cancel();
    _viewportTimer = Timer(const Duration(milliseconds: 250), _emitViewState);
  }

  int _groupNumberFor(String groupId) {
    final scoreRows = _document.rows
        .where((item) => item.type == SmartGridRowType.score)
        .toList();
    return scoreRows.indexWhere((item) => item.groupId == groupId) + 1;
  }

  void _emitViewState() {
    final selected = _selected ?? (0, 0);
    _emitDocumentViewState(_document.copyWith(
      selectedRow: selected.$1,
      selectedColumn: selected.$2,
      horizontalOffset: _horizontal.hasClients ? _horizontal.offset : 0,
      verticalOffset: _vertical.hasClients ? _vertical.offset : 0,
    ));
  }

  void _emitDocumentViewState(SmartGridDocument document) {
    _latestDocument = document;
    final callback = widget.onViewStateChanged;
    if (callback != null) {
      callback(document);
      return;
    }
    widget.onChanged(document);
  }
}

class _ScorePickerResult {
  const _ScorePickerResult.value(this.value) : clear = false;
  const _ScorePickerResult.clear()
      : value = null,
        clear = true;

  final String? value;
  final bool clear;
}

class _ScoreCellPicker extends StatefulWidget {
  const _ScoreCellPicker();

  @override
  State<_ScoreCellPicker> createState() => _ScoreCellPickerState();
}

class _ScoreCellPickerState extends State<_ScoreCellPicker> {
  String? _degree;

  void _pickValue(String value) {
    Navigator.of(context).pop(_ScorePickerResult.value(value));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: theme.colorScheme.surface,
      child: ConstrainedBox(
        constraints: const BoxConstraints.tightFor(width: 288),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('选择数字简谱', style: theme.textTheme.titleSmall),
              const SizedBox(height: 8),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final degree in ['1', '2', '3', '4', '5', '6', '7'])
                    ChoiceChip(
                      key: Key('score-picker-number-$degree'),
                      label: Text(degree),
                      selected: _degree == degree,
                      onSelected: (_) => setState(() => _degree = degree),
                    ),
                  ActionChip(
                    key: const Key('score-picker-rest'),
                    label: const Text('0 休止'),
                    onPressed: () => _pickValue('0'),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Text('音区', style: theme.textTheme.labelLarge),
              const SizedBox(height: 4),
              Wrap(
                spacing: 6,
                children: [
                  for (final register in [
                    ('low', '低音', ','),
                    ('middle', '中音', ''),
                    ('high', '高音', "'"),
                  ])
                    ActionChip(
                      key: Key('score-picker-register-${register.$1}'),
                      label: Text(register.$2),
                      onPressed: _degree == null
                          ? null
                          : () => _pickValue('$_degree${register.$3}'),
                    ),
                ],
              ),
              const SizedBox(height: 12),
              Text('结构符号', style: theme.textTheme.labelLarge),
              const SizedBox(height: 4),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final symbol in ['-', '|', '//'])
                    ActionChip(
                      key: Key('score-picker-symbol-$symbol'),
                      label: Text(symbol),
                      onPressed: () => _pickValue(symbol),
                    ),
                  ActionChip(
                    key: const Key('score-picker-clear'),
                    label: const Text('清空'),
                    onPressed: () => Navigator.of(context).pop(
                      const _ScorePickerResult.clear(),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class SmartGridOutputView extends StatefulWidget {
  final SmartGridDocument document;
  final SmartGridConversion conversion;
  final void Function(int row, int column)? onCellTap;
  final ResizablePanelSize panelSize;
  final ValueChanged<ResizablePanelSize>? onPanelSizeChanged;
  final TableScale scale;

  const SmartGridOutputView({
    super.key,
    required this.document,
    required this.conversion,
    this.onCellTap,
    this.panelSize = const ResizablePanelSize(),
    this.onPanelSizeChanged,
    this.scale = const TableScale(),
  });

  @override
  State<SmartGridOutputView> createState() => _SmartGridOutputViewState();
}

class _SmartGridOutputViewState extends State<SmartGridOutputView> {
  double get _cellSize => widget.scale.dimension(58);
  double get _indexWidth => widget.scale.dimension(46);
  double get _typeWidth => widget.scale.dimension(86);
  double get _headerHeight => widget.scale.dimension(38);
  final _horizontal = ScrollController();
  final _vertical = ScrollController();
  final _frozenVertical = ScrollController();
  late final TableScrollLink _verticalLink;

  @override
  void initState() {
    super.initState();
    _verticalLink = TableScrollLink(_vertical, _frozenVertical);
  }

  @override
  void dispose() {
    _verticalLink.dispose();
    _horizontal.dispose();
    _vertical.dispose();
    _frozenVertical.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ResizablePanel(
      panelId: 'letter-grid',
      size: widget.panelSize,
      onSizeChanged: widget.onPanelSizeChanged ?? (_) {},
      child: Container(
        decoration: BoxDecoration(
            border:
                Border.all(color: Theme.of(context).colorScheme.outlineVariant),
            borderRadius: BorderRadius.circular(8)),
        child: TableScrollFrame(
          horizontalController: _horizontal,
          verticalController: _vertical,
          headerHeight: _headerHeight,
          child: Stack(
            children: [
              SingleChildScrollView(
                controller: _horizontal,
                scrollDirection: Axis.horizontal,
                child: SizedBox(
                  width: _indexWidth +
                      _typeWidth +
                      widget.document.columnCount * _cellSize,
                  child: Column(children: [
                    SizedBox(
                        height: _headerHeight,
                        child: Row(children: [
                          _cell(context, '#', _indexWidth, header: true),
                          _cell(context, '类型', _typeWidth, header: true),
                          for (var column = 0;
                              column < widget.document.columnCount;
                              column++)
                            _cell(context, smartGridColumnLabel(column),
                                _cellSize,
                                header: true),
                        ])),
                    Expanded(
                      child: ListView.builder(
                        controller: _vertical,
                        itemCount: widget.document.rows.length,
                        itemBuilder: (context, row) => SizedBox(
                          height: _cellSize,
                          child: Row(children: [
                            _cell(context, '${row + 1}', _indexWidth,
                                header: true),
                            _cell(context, _rowLabel(row), _typeWidth,
                                header: true),
                            for (var column = 0;
                                column < widget.document.columnCount;
                                column++)
                              _outputCell(context, row, column, _cellSize),
                          ]),
                        ),
                      ),
                    ),
                  ]),
                ),
              ),
              Positioned(
                left: 0,
                top: 0,
                bottom: 0,
                width: _indexWidth + _typeWidth,
                child: NotificationListener<ScrollNotification>(
                  onNotification: (_) => true,
                  child: ColoredBox(
                    color: Theme.of(context).colorScheme.surface,
                    child: Column(children: [
                      SizedBox(
                        height: _headerHeight,
                        child: Row(children: [
                          _cell(context, '#', _indexWidth, header: true),
                          _cell(context, '类型', _typeWidth, header: true),
                        ]),
                      ),
                      Expanded(
                        child: ListView.builder(
                          controller: _frozenVertical,
                          itemCount: widget.document.rows.length,
                          itemBuilder: (context, row) => SizedBox(
                            height: _cellSize,
                            child: Row(children: [
                              _cell(context, '${row + 1}', _indexWidth,
                                  header: true),
                              _cell(context, _rowLabel(row), _typeWidth,
                                  header: true),
                            ]),
                          ),
                        ),
                      ),
                    ]),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _outputCell(BuildContext context, int row, int column, double size) {
    final issue = widget.conversion.issues
        .where((item) => item.row == row && item.column == column)
        .firstOrNull;
    final color = issue?.severity == SmartGridIssueSeverity.error
        ? Theme.of(context).colorScheme.errorContainer
        : issue != null
            ? Colors.amber.shade100
            : Theme.of(context).colorScheme.surface;
    return Tooltip(
      message: issue?.message ?? '${smartGridColumnLabel(column)}${row + 1}',
      child: InkWell(
        onTap: () => widget.onCellTap?.call(row, column),
        child: Container(
          width: size,
          alignment: Alignment.center,
          decoration: BoxDecoration(
              color: color,
              border: Border.all(
                  color: Theme.of(context).colorScheme.outlineVariant)),
          child: Stack(
            alignment: Alignment.center,
            children: [
              Text(
                widget.conversion.outputRows[row][column],
                textAlign: TextAlign.center,
                overflow: TextOverflow.ellipsis,
                style:
                    AppTypography.of(context).gridCellAt(widget.scale.font(16)),
              ),
              if (issue != null)
                Positioned(
                  right: 2,
                  top: 2,
                  child: Icon(
                    issue.severity == SmartGridIssueSeverity.error
                        ? Icons.error
                        : Icons.warning_amber_rounded,
                    size: widget.scale.dimension(13),
                    color: issue.severity == SmartGridIssueSeverity.error
                        ? Theme.of(context).colorScheme.error
                        : Colors.amber.shade900,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _cell(BuildContext context, String text, double width,
          {bool header = false}) =>
      Container(
        width: width,
        alignment: Alignment.center,
        decoration: BoxDecoration(
            color: header
                ? Theme.of(context).colorScheme.surfaceContainerHighest
                : null,
            border: Border.all(
                color: Theme.of(context).colorScheme.outlineVariant)),
        child: Text(
          text,
          overflow: TextOverflow.ellipsis,
          style: header
              ? AppTypography.of(context).gridHeaderAt(widget.scale.font(14))
              : AppTypography.of(context).gridCellAt(widget.scale.font(16)),
        ),
      );

  int _groupNumber(String groupId) {
    final groups = <String>[];
    for (final row in widget.document.rows) {
      if (row.type == SmartGridRowType.score && !groups.contains(row.groupId)) {
        groups.add(row.groupId);
      }
    }
    final index = groups.indexOf(groupId);
    return index < 0 ? 0 : index + 1;
  }

  String _rowLabel(int row) =>
      '${widget.document.rows[row].type == SmartGridRowType.score ? '谱' : '词'} · '
      '${_groupNumber(widget.document.rows[row].groupId)}';
}

extension<T> on Iterable<T> {
  T? get firstOrNull {
    final iterator = this.iterator;
    return iterator.moveNext() ? iterator.current : null;
  }
}
