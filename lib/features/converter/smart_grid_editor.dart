import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'smart_grid_converter.dart';
import 'smart_grid_codec.dart';
import 'smart_grid_document.dart';
import 'resizable_panel.dart';

class SmartGridEditor extends StatefulWidget {
  final SmartGridDocument document;
  final ValueChanged<SmartGridDocument> onChanged;
  final ValueChanged<SmartGridDocument>? onViewStateChanged;
  final List<SmartGridIssue> issues;
  final ValueChanged<(int, int)>? onSelectionChanged;
  final ResizablePanelSize panelSize;
  final ValueChanged<ResizablePanelSize>? onPanelSizeChanged;

  const SmartGridEditor({
    super.key,
    required this.document,
    required this.onChanged,
    this.onViewStateChanged,
    this.issues = const [],
    this.onSelectionChanged,
    this.panelSize = const ResizablePanelSize(),
    this.onPanelSizeChanged,
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
  final _undo = <SmartGridDocument>[];
  final _redo = <SmartGridDocument>[];
  Timer? _viewportTimer;
  Timer? _cellLongPressTimer;
  int? _cellLongPressPointer;
  (int, int)? _selected;
  (int, int)? _selectionAnchor;
  double _cellSize = 58;
  bool _syncingVertical = false;

  @override
  void initState() {
    super.initState();
    _selected = (
      widget.document.selectedRow,
      widget.document.selectedColumn,
    );
    _selectionAnchor = _selected;
    _horizontal.addListener(_scheduleViewportSave);
    _vertical.addListener(_scheduleViewportSave);
    _vertical.addListener(() => _syncVertical(_vertical, _frozenVertical));
    _frozenVertical
        .addListener(() => _syncVertical(_frozenVertical, _vertical));
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (_horizontal.hasClients) {
        _horizontal.jumpTo(widget.document.horizontalOffset.clamp(
          0,
          _horizontal.position.maxScrollExtent,
        ));
      }
      if (_vertical.hasClients) {
        _vertical.jumpTo(widget.document.verticalOffset.clamp(
          0,
          _vertical.position.maxScrollExtent,
        ));
      }
    });
  }

  @override
  void didUpdateWidget(covariant SmartGridEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    final documentSelection = (
      widget.document.selectedRow,
      widget.document.selectedColumn,
    );
    if (_selected != documentSelection) {
      _selected = documentSelection;
      _selectionAnchor = documentSelection;
    }
    if (oldWidget.document.rows.first.id != widget.document.rows.first.id) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        if (_horizontal.hasClients) {
          _horizontal.jumpTo(widget.document.horizontalOffset.clamp(
            0,
            _horizontal.position.maxScrollExtent,
          ));
        }
        if (_vertical.hasClients) {
          _vertical.jumpTo(widget.document.verticalOffset.clamp(
            0,
            _vertical.position.maxScrollExtent,
          ));
        }
      });
    }
    for (var row = 0; row < widget.document.rows.length; row++) {
      for (var column = 0; column < widget.document.columnCount; column++) {
        final key = _cellKey(row, column);
        final controller = _controllers[key];
        final value = widget.document.rows[row].cells[column];
        if (controller != null && controller.text != value) {
          controller.value = TextEditingValue(
            text: value,
            selection: TextSelection.collapsed(offset: value.length),
          );
        }
      }
    }
  }

  @override
  void dispose() {
    _viewportTimer?.cancel();
    _cellLongPressTimer?.cancel();
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
        row >= widget.document.rows.length ||
        column < 0 ||
        column >= widget.document.columnCount) {
      return;
    }
    final key = _cellKey(row, column);
    _focusNodes.putIfAbsent(key, FocusNode.new).requestFocus();
    setState(() {
      _selected = (row, column);
      if (!extendSelection || _selectionAnchor == null) {
        _selectionAnchor = (row, column);
      }
    });
    widget.onSelectionChanged?.call((row, column));
    _emitViewState();
  }

  void _apply(SmartGridDocument next, {bool recordHistory = true}) {
    if (recordHistory) {
      _undo.add(widget.document);
      if (_undo.length > 100) _undo.removeAt(0);
      _redo.clear();
    }
    widget.onChanged(next);
  }

  void _undoOnce() {
    if (_undo.isEmpty) return;
    final previous = _undo.removeLast();
    _redo.add(widget.document);
    _apply(previous, recordHistory: false);
  }

  void _redoOnce() {
    if (_redo.isEmpty) return;
    final next = _redo.removeLast();
    _undo.add(widget.document);
    _apply(next, recordHistory: false);
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
              onPressed: () => _apply(widget.document.addRow()),
              icon: const Icon(Icons.add),
              label: const Text('添加行'),
            ),
            OutlinedButton.icon(
              key: const Key('grid-add-column'),
              onPressed: () => _apply(widget.document.addColumn()),
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
            SegmentedButton<double>(
              segments: const [
                ButtonSegment(value: 48, label: Text('小')),
                ButtonSegment(value: 58, label: Text('中')),
                ButtonSegment(value: 70, label: Text('大')),
              ],
              selected: {_cellSize},
              onSelectionChanged: (value) =>
                  setState(() => _cellSize = value.first),
              showSelectedIcon: false,
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
              child: Stack(
                children: [
                  Scrollbar(
                    controller: _horizontal,
                    thumbVisibility: true,
                    notificationPredicate: (notification) =>
                        notification.metrics.axis == Axis.horizontal,
                    child: SingleChildScrollView(
                      controller: _horizontal,
                      scrollDirection: Axis.horizontal,
                      child: SizedBox(
                        width:
                            46 + 86 + widget.document.columnCount * _cellSize,
                        child: Column(children: [
                          _header(context),
                          Expanded(
                            child: Scrollbar(
                              controller: _vertical,
                              thumbVisibility: true,
                              child: ReorderableListView.builder(
                                scrollController: _vertical,
                                buildDefaultDragHandles: false,
                                itemCount: widget.document.rows.length,
                                itemBuilder: (context, row) => KeyedSubtree(
                                  key: ValueKey(widget.document.rows[row].id),
                                  child: _row(context, row),
                                ),
                                onReorderItem: (oldIndex, newIndex) => _apply(
                                  widget.document
                                      .reorderGroup(oldIndex, newIndex),
                                ),
                              ),
                            ),
                          ),
                        ]),
                      ),
                    ),
                  ),
                  Positioned(
                    left: 0,
                    top: 0,
                    bottom: 0,
                    width: 132,
                    child: _frozenPane(context),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 6),
          const Text(
              '提示：Enter 向下、Tab 向右；可粘贴由制表符和换行组成的表格。右键或长按格子可移动单元格，Ctrl + 加号／减号可打开插入／删除菜单。'),
        ]),
      ),
    );
  }

  Widget _header(BuildContext context) {
    final color = Theme.of(context).colorScheme.surfaceContainerHighest;
    return SizedBox(
      height: 38,
      child: Row(children: [
        _headerCell('#', 46, color),
        _headerCell('类型', 86, color),
        for (var column = 0; column < widget.document.columnCount; column++)
          InkWell(
            onLongPress: () => _showColumnMenu(column),
            child: _headerCell(smartGridColumnLabel(column), _cellSize, color),
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
          height: 38,
          child: Row(children: [
            _headerCell('#', 46, headerColor),
            _headerCell('类型', 86, headerColor),
          ]),
        ),
        Expanded(
          child: ReorderableListView.builder(
            scrollController: _frozenVertical,
            buildDefaultDragHandles: false,
            itemCount: widget.document.rows.length,
            itemBuilder: (context, row) => KeyedSubtree(
              key: ValueKey('frozen-${widget.document.rows[row].id}'),
              child: _frozenRow(context, row),
            ),
            onReorderItem: (oldIndex, newIndex) => _apply(
              widget.document.reorderGroup(oldIndex, newIndex),
            ),
          ),
        ),
      ]),
    );
  }

  Widget _frozenRow(BuildContext context, int rowIndex) {
    final row = widget.document.rows[rowIndex];
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
              child: InkWell(
                onLongPress: () => _showRowMenu(rowIndex),
                child: _headerCell('${rowIndex + 1}', 46, tint),
              ),
            ),
          ),
          SizedBox(
            width: 86,
            child: Padding(
              padding: const EdgeInsets.all(4),
              child: DropdownButtonFormField<SmartGridRowType>(
                initialValue: row.type,
                isDense: true,
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  contentPadding:
                      EdgeInsets.symmetric(horizontal: 6, vertical: 8),
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
                    _apply(widget.document.setRowType(rowIndex, value));
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
    final row = widget.document.rows[rowIndex];
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
              child: InkWell(
                onLongPress: () => _showRowMenu(rowIndex),
                child: _headerCell('${rowIndex + 1}', 46, tint),
              ),
            ),
          ),
          SizedBox(
            width: 86,
            child: Padding(
              padding: const EdgeInsets.all(4),
              child: DropdownButtonFormField<SmartGridRowType>(
                initialValue: row.type,
                isDense: true,
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  contentPadding:
                      EdgeInsets.symmetric(horizontal: 6, vertical: 8),
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
                    _apply(widget.document.setRowType(rowIndex, value));
                  }
                },
              ),
            ),
          ),
          for (var column = 0; column < widget.document.columnCount; column++)
            _editableCell(context, rowIndex, column),
        ]),
      ),
    );
  }

  Widget _editableCell(BuildContext context, int row, int column) {
    final value = widget.document.rows[row].cells[column];
    final issue = widget.issues
        .where((item) => item.row == row && item.column == column)
        .firstOrNull;
    final selected = _isCellSelected(row, column);
    final borderColor = issue?.severity == SmartGridIssueSeverity.error
        ? Theme.of(context).colorScheme.error
        : issue != null
            ? Colors.amber.shade800
            : selected
                ? Theme.of(context).colorScheme.primary
                : Theme.of(context).colorScheme.outlineVariant;
    final key = _cellKey(row, column);
    final focusNode = _focusNodes.putIfAbsent(key, FocusNode.new);
    final controller = _controllers.putIfAbsent(
      key,
      () => TextEditingController(text: value),
    );
    return Listener(
      onPointerDown: (event) => _startCellLongPress(event, row, column),
      onPointerUp: _stopCellLongPress,
      onPointerCancel: _stopCellLongPress,
      child: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onSecondaryTap: () => _openCellOperationMenuFor(row, column),
        child: Tooltip(
          message:
              issue?.message ?? '${smartGridColumnLabel(column)}${row + 1}',
          child: Container(
            width: _cellSize,
            height: _cellSize,
            decoration: BoxDecoration(
                border: Border.all(
                    color: borderColor,
                    width: issue != null || selected ? 2 : 1)),
            padding: const EdgeInsets.all(3),
            child: Stack(
              children: [
                Positioned.fill(
                  child: TextFormField(
                    key: ValueKey('grid-cell-$key'),
                    focusNode: focusNode,
                    controller: controller,
                    textAlign: TextAlign.center,
                    textAlignVertical: TextAlignVertical.center,
                    enableInteractiveSelection: false,
                    maxLines: 1,
                    style: TextStyle(fontSize: value.length > 4 ? 11 : 16),
                    decoration: const InputDecoration(
                        border: InputBorder.none,
                        contentPadding: EdgeInsets.zero,
                        isDense: true),
                    inputFormatters: [
                      FilteringTextInputFormatter.deny(RegExp(r'[\r\n\t]'))
                    ],
                    onTap: () {
                      setState(() {
                        _selected = (row, column);
                        _selectionAnchor = (row, column);
                      });
                      widget.onSelectionChanged?.call((row, column));
                      _emitViewState();
                    },
                    onChanged: (next) {
                      _apply(widget.document.setCell(row, column, next));
                      if (_isSingleCjk(next)) {
                        WidgetsBinding.instance.addPostFrameCallback((_) {
                          if (mounted && _selected == (row, column)) {
                            _move(0, 1);
                          }
                        });
                      }
                    },
                    onFieldSubmitted: (_) => focusCell(
                        (row + 1).clamp(0, widget.document.rows.length - 1),
                        column),
                  ),
                ),
                if (issue != null)
                  Positioned(
                    right: 0,
                    top: 0,
                    child: IgnorePointer(
                      child: Icon(
                        issue.severity == SmartGridIssueSeverity.error
                            ? Icons.error
                            : Icons.warning_amber_rounded,
                        size: 13,
                        color: borderColor,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _startCellLongPress(PointerDownEvent event, int row, int column) {
    _cellLongPressTimer?.cancel();
    _cellLongPressPointer = event.pointer;
    _cellLongPressTimer = Timer(const Duration(milliseconds: 500), () {
      if (!mounted || _cellLongPressPointer != event.pointer) return;
      _cellLongPressPointer = null;
      _openCellOperationMenuFor(row, column);
    });
  }

  void _stopCellLongPress(PointerEvent event) {
    if (_cellLongPressPointer != event.pointer) return;
    _cellLongPressTimer?.cancel();
    _cellLongPressPointer = null;
  }

  Future<void> _showRowMenu(int row) async {
    final action = await showModalBottomSheet<String>(
      context: context,
      builder: (context) => SafeArea(
          child: Wrap(children: [
        ListTile(
            leading: const Icon(Icons.vertical_align_top),
            title: const Text('在上方插入谱行'),
            onTap: () => Navigator.pop(context, 'score-above')),
        ListTile(
            leading: const Icon(Icons.vertical_align_top),
            title: const Text('在上方插入词行'),
            onTap: () => Navigator.pop(context, 'lyrics-above')),
        ListTile(
            leading: const Icon(Icons.vertical_align_bottom),
            title: const Text('在下方插入谱行'),
            onTap: () => Navigator.pop(context, 'score-below')),
        ListTile(
            leading: const Icon(Icons.lyrics_outlined),
            title: const Text('在下方插入词行'),
            onTap: () => Navigator.pop(context, 'lyrics-below')),
        ListTile(
            leading: const Icon(Icons.delete_outline),
            title: const Text('删除此行'),
            onTap: () => Navigator.pop(context, 'delete')),
        ListTile(
            leading: const Icon(Icons.clear_all),
            title: const Text('清空此行'),
            onTap: () => Navigator.pop(context, 'clear')),
      ])),
    );
    if (action == 'score-above') {
      _apply(widget.document.insertRow(row, SmartGridRowType.score));
    }
    if (action == 'lyrics-above') {
      _apply(widget.document.insertRow(row, SmartGridRowType.lyrics));
    }
    if (action == 'score-below') {
      _apply(widget.document.insertRow(row + 1, SmartGridRowType.score));
    }
    if (action == 'lyrics-below') {
      _apply(widget.document.insertRow(row + 1, SmartGridRowType.lyrics));
    }
    if (action == 'delete') _apply(widget.document.deleteRow(row));
    if (action == 'clear') {
      var next = widget.document;
      for (var column = 0; column < next.columnCount; column++) {
        next = next.setCell(row, column, '');
      }
      _apply(next);
    }
  }

  Future<void> _showColumnMenu(int column) async {
    final action = await showModalBottomSheet<String>(
      context: context,
      builder: (context) => SafeArea(
        child: Wrap(children: [
          ListTile(
            leading: const Icon(Icons.keyboard_arrow_left),
            title: const Text('在左侧插入一列'),
            onTap: () => Navigator.pop(context, 'insert-left'),
          ),
          ListTile(
            leading: const Icon(Icons.keyboard_arrow_right),
            title: const Text('在右侧插入一列'),
            onTap: () => Navigator.pop(context, 'insert-right'),
          ),
          ListTile(
            leading: const Icon(Icons.delete_outline),
            title: const Text('删除此列'),
            onTap: () => Navigator.pop(context, 'delete'),
          ),
          ListTile(
            leading: const Icon(Icons.clear_all),
            title: const Text('清空此列'),
            onTap: () => Navigator.pop(context, 'clear'),
          ),
        ]),
      ),
    );
    if (action == 'insert-left') {
      _apply(widget.document.insertColumn(column));
    }
    if (action == 'insert-right') {
      _apply(widget.document.insertColumn(column + 1));
    }
    if (action == 'delete') {
      _apply(widget.document.deleteColumn(column));
    }
    if (action == 'clear') {
      var next = widget.document;
      for (var row = 0; row < next.rows.length; row++) {
        next = next.setCell(row, column, '');
      }
      _apply(next);
    }
  }

  bool get _hasSingleCellSelection =>
      _selected != null && _selected == _selectionAnchor;

  void _openCellOperationMenuFor(int row, int column) {
    focusCell(row, column);
    unawaited(_showCellOperationMenu());
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
    final next = widget.document.applyCellOperation(
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
      for (var source = row; source < widget.document.rows.length; source++) {
        final value = widget.document.rows[source].cells[column];
        final targetType = source + 1 < widget.document.rows.length
            ? widget.document.rows[source + 1].type
            : widget.document.rows.last.type;
        if (_isInvalidAfterRowMove(targetType, value)) {
          return true;
        }
      }
    }
    if (operation == SmartGridCellOperation.deleteAllRowsUp) {
      for (var source = row + 1;
          source < widget.document.rows.length;
          source++) {
        final value = widget.document.rows[source].cells[column];
        final targetType = widget.document.rows[source - 1].type;
        if (_isInvalidAfterRowMove(targetType, value)) {
          return true;
        }
      }
    }
    return false;
  }

  bool _isInvalidAfterRowMove(SmartGridRowType targetType, String value) {
    if (value.isEmpty) return false;
    if (validateSmartGridCell(targetType, value) != null) return true;
    return targetType == SmartGridRowType.lyrics &&
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
      (selected.$1 + rowDelta).clamp(0, widget.document.rows.length - 1),
      (selected.$2 + columnDelta).clamp(0, widget.document.columnCount - 1),
      extendSelection: extendSelection,
    );
  }

  void _copySelectedCell() {
    final bounds = _selectionBounds();
    if (bounds == null) return;
    final rows = <String>[];
    for (var row = bounds.$1; row <= bounds.$2; row++) {
      rows.add(widget.document.rows[row].cells
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
    var next = widget.document;
    for (var row = bounds.$1; row <= bounds.$2; row++) {
      for (var column = bounds.$3; column <= bounds.$4; column++) {
        next = next.setCell(row, column, '');
      }
    }
    _apply(next);
  }

  void _selectAll() {
    setState(() {
      _selectionAnchor = (0, 0);
      _selected = (
        widget.document.rows.length - 1,
        widget.document.columnCount - 1,
      );
    });
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
    final matrix = lines.map((line) {
      if (line.contains('\t')) return line.split('\t');
      final trimmed = line.trim();
      if (RegExp(r'^[\u3400-\u9fff]+$').hasMatch(trimmed) &&
          trimmed.runes.length > 1) {
        return trimmed.runes.map(String.fromCharCode).toList();
      }
      return trimmed.split(RegExp(r'\s+'));
    }).toList();
    final neededColumns = matrix.fold<int>(
      0,
      (width, row) => row.length > width ? row.length : width,
    );
    var next = widget.document.ensureSize(
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
    _apply(next);
    final lastRow =
        (selected.$1 + matrix.length - 1).clamp(0, next.rows.length - 1);
    final lastColumn =
        (selected.$2 + neededColumns - 1).clamp(0, next.columnCount - 1);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) focusCell(lastRow, lastColumn);
    });
  }

  Widget _headerCell(String text, double width, Color color) => Container(
        width: width,
        alignment: Alignment.center,
        decoration: BoxDecoration(
            color: color,
            border: Border.all(
                color: Theme.of(context).colorScheme.outlineVariant)),
        child: Text(text, style: const TextStyle(fontWeight: FontWeight.w600)),
      );

  String _cellKey(int row, int column) =>
      '${widget.document.rows[row].id}:$column';

  void _scheduleViewportSave() {
    _viewportTimer?.cancel();
    _viewportTimer = Timer(const Duration(milliseconds: 250), _emitViewState);
  }

  void _syncVertical(ScrollController source, ScrollController target) {
    if (_syncingVertical || !source.hasClients || !target.hasClients) return;
    final offset = source.offset.clamp(0.0, target.position.maxScrollExtent);
    if ((target.offset - offset).abs() < .5) return;
    _syncingVertical = true;
    target.jumpTo(offset);
    _syncingVertical = false;
  }

  int _groupNumberFor(String groupId) {
    final scoreRows = widget.document.rows
        .where((item) => item.type == SmartGridRowType.score)
        .toList();
    return scoreRows.indexWhere((item) => item.groupId == groupId) + 1;
  }

  void _emitViewState() {
    final selected = _selected ?? (0, 0);
    widget.onViewStateChanged?.call(widget.document.copyWith(
      selectedRow: selected.$1,
      selectedColumn: selected.$2,
      horizontalOffset: _horizontal.hasClients ? _horizontal.offset : 0,
      verticalOffset: _vertical.hasClients ? _vertical.offset : 0,
    ));
  }

  bool _isSingleCjk(String value) =>
      value.runes.length == 1 && RegExp(r'[\u3400-\u9fff]').hasMatch(value);
}

class SmartGridOutputView extends StatefulWidget {
  final SmartGridDocument document;
  final SmartGridConversion conversion;
  final void Function(int row, int column)? onCellTap;
  final ResizablePanelSize panelSize;
  final ValueChanged<ResizablePanelSize>? onPanelSizeChanged;

  const SmartGridOutputView({
    super.key,
    required this.document,
    required this.conversion,
    this.onCellTap,
    this.panelSize = const ResizablePanelSize(),
    this.onPanelSizeChanged,
  });

  @override
  State<SmartGridOutputView> createState() => _SmartGridOutputViewState();
}

class _SmartGridOutputViewState extends State<SmartGridOutputView> {
  static const _cellSize = 58.0;
  final _horizontal = ScrollController();
  final _vertical = ScrollController();
  final _frozenVertical = ScrollController();
  bool _syncingVertical = false;

  @override
  void initState() {
    super.initState();
    _vertical.addListener(() => _syncVertical(_vertical, _frozenVertical));
    _frozenVertical
        .addListener(() => _syncVertical(_frozenVertical, _vertical));
  }

  @override
  void dispose() {
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
        child: Stack(
          children: [
            SingleChildScrollView(
              controller: _horizontal,
              scrollDirection: Axis.horizontal,
              child: SizedBox(
                width: 132 + widget.document.columnCount * _cellSize,
                child: Column(children: [
                  SizedBox(
                      height: 38,
                      child: Row(children: [
                        _cell(context, '#', 46, header: true),
                        _cell(context, '类型', 86, header: true),
                        for (var column = 0;
                            column < widget.document.columnCount;
                            column++)
                          _cell(
                              context, smartGridColumnLabel(column), _cellSize,
                              header: true),
                      ])),
                  Expanded(
                    child: ListView.builder(
                      controller: _vertical,
                      itemCount: widget.document.rows.length,
                      itemBuilder: (context, row) => SizedBox(
                        height: _cellSize,
                        child: Row(children: [
                          _cell(context, '${row + 1}', 46, header: true),
                          _cell(context, _rowLabel(row), 86, header: true),
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
              width: 132,
              child: ColoredBox(
                color: Theme.of(context).colorScheme.surface,
                child: Column(children: [
                  SizedBox(
                    height: 38,
                    child: Row(children: [
                      _cell(context, '#', 46, header: true),
                      _cell(context, '类型', 86, header: true),
                    ]),
                  ),
                  Expanded(
                    child: ListView.builder(
                      controller: _frozenVertical,
                      itemCount: widget.document.rows.length,
                      itemBuilder: (context, row) => SizedBox(
                        height: _cellSize,
                        child: Row(children: [
                          _cell(context, '${row + 1}', 46, header: true),
                          _cell(context, _rowLabel(row), 86, header: true),
                        ]),
                      ),
                    ),
                  ),
                ]),
              ),
            ),
          ],
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
              Text(widget.conversion.outputRows[row][column],
                  textAlign: TextAlign.center),
              if (issue != null)
                Positioned(
                  right: 2,
                  top: 2,
                  child: Icon(
                    issue.severity == SmartGridIssueSeverity.error
                        ? Icons.error
                        : Icons.warning_amber_rounded,
                    size: 13,
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
        child: Text(text,
            style:
                header ? const TextStyle(fontWeight: FontWeight.w600) : null),
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

  void _syncVertical(ScrollController source, ScrollController target) {
    if (_syncingVertical || !source.hasClients || !target.hasClients) return;
    final offset = source.offset.clamp(0.0, target.position.maxScrollExtent);
    if ((target.offset - offset).abs() < .5) return;
    _syncingVertical = true;
    target.jumpTo(offset);
    _syncingVertical = false;
  }
}

extension<T> on Iterable<T> {
  T? get firstOrNull {
    final iterator = this.iterator;
    return iterator.moveNext() ? iterator.current : null;
  }
}
