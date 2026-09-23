enum SmartGridRowType { score, lyrics }

/// A single-cell operation that shifts only the affected row or column.
enum SmartGridCellOperation {
  insertRowRight,
  insertSameTypeDown,
  insertAllRowsDown,
  deleteRowLeft,
  deleteSameTypeUp,
  deleteAllRowsUp;

  bool get inserts => switch (this) {
        insertRowRight || insertSameTypeDown || insertAllRowsDown => true,
        deleteRowLeft || deleteSameTypeUp || deleteAllRowsUp => false,
      };

  bool get movesAllRowTypes =>
      this == insertAllRowsDown || this == deleteAllRowsUp;
}

class SmartGridRow {
  final String id;
  final String groupId;
  final SmartGridRowType type;
  final List<String> cells;

  const SmartGridRow({
    required this.id,
    required this.groupId,
    required this.type,
    required this.cells,
  });

  SmartGridRow copyWith({
    String? groupId,
    SmartGridRowType? type,
    List<String>? cells,
  }) {
    return SmartGridRow(
      id: id,
      groupId: groupId ?? this.groupId,
      type: type ?? this.type,
      cells: List.unmodifiable(cells ?? this.cells),
    );
  }

  Map<String, Object?> toJson() => {
        'id': id,
        'groupId': groupId,
        'type': type.name,
        'cells': cells,
      };

  static SmartGridRow? fromJson(Object? value) {
    if (value is! Map ||
        value['id'] is! String ||
        value['groupId'] is! String ||
        value['type'] is! String ||
        value['cells'] is! List ||
        (value['cells'] as List).any((cell) => cell is! String)) {
      return null;
    }
    final type = SmartGridRowType.values
        .where((item) => item.name == value['type'])
        .firstOrNull;
    if (type == null) return null;
    return SmartGridRow(
      id: value['id'] as String,
      groupId: value['groupId'] as String,
      type: type,
      cells: List.unmodifiable((value['cells'] as List).cast<String>()),
    );
  }
}

class SmartGridDocument {
  static const jsonVersion = 2;
  static const maxRows = 500;
  static const maxColumns = 500;

  final List<SmartGridRow> rows;
  final int columnCount;
  final int selectedRow;
  final int selectedColumn;
  final double horizontalOffset;
  final double verticalOffset;

  const SmartGridDocument({
    required this.rows,
    required this.columnCount,
    this.selectedRow = 0,
    this.selectedColumn = 0,
    this.horizontalOffset = 0,
    this.verticalOffset = 0,
  });

  factory SmartGridDocument.empty({int rows = 4, int columns = 16}) {
    return SmartGridDocument(
      columnCount: columns,
      rows: List.generate(rows, (index) {
        final pair = index ~/ 2 + 1;
        return SmartGridRow(
          id: 'row-${index + 1}',
          groupId: 'group-$pair',
          type: index.isEven ? SmartGridRowType.score : SmartGridRowType.lyrics,
          cells: List.filled(columns, ''),
        );
      }),
    );
  }

  bool get isEmpty => rows.every(
        (row) => row.cells.every((cell) => cell.trim().isEmpty),
      );

  SmartGridDocument setCell(int rowIndex, int columnIndex, String value) {
    final normalized = value.replaceAll(RegExp(r'[\r\n\t]'), '').trim();
    final nextRows = [...rows];
    final cells = [...nextRows[rowIndex].cells];
    cells[columnIndex] = normalized == '_' ? '' : normalized;
    nextRows[rowIndex] = nextRows[rowIndex].copyWith(cells: cells);
    return copyWith(rows: nextRows);
  }

  SmartGridDocument setRowType(int rowIndex, SmartGridRowType type) {
    final nextRows = [...rows];
    nextRows[rowIndex] = nextRows[rowIndex].copyWith(type: type);
    return copyWith(rows: _repairGroups(nextRows));
  }

  SmartGridDocument addRow() {
    if (rows.length >= maxRows) return this;
    final nextType = rows.isEmpty || rows.last.type == SmartGridRowType.lyrics
        ? SmartGridRowType.score
        : SmartGridRowType.lyrics;
    final serial = rows.length + 1;
    final groupId = nextType == SmartGridRowType.lyrics && rows.isNotEmpty
        ? rows.last.groupId
        : 'group-$serial';
    return copyWith(rows: [
      ...rows,
      SmartGridRow(
        id: 'row-${DateTime.now().microsecondsSinceEpoch}-$serial',
        groupId: groupId,
        type: nextType,
        cells: List.filled(columnCount, ''),
      ),
    ]);
  }

  SmartGridDocument insertRow(int index, SmartGridRowType type) {
    if (rows.length >= maxRows) return this;
    final safeIndex = index.clamp(0, rows.length);
    final groupId = type == SmartGridRowType.lyrics && safeIndex > 0
        ? rows[safeIndex - 1].groupId
        : 'group-${DateTime.now().microsecondsSinceEpoch}';
    final row = SmartGridRow(
      id: 'row-${DateTime.now().microsecondsSinceEpoch}-$safeIndex',
      groupId: groupId,
      type: type,
      cells: List.filled(columnCount, ''),
    );
    final nextRows = [...rows]..insert(safeIndex, row);
    return copyWith(
      rows: _repairGroups(nextRows),
      selectedRow: safeIndex <= selectedRow ? selectedRow + 1 : selectedRow,
    );
  }

  SmartGridDocument deleteRow(int rowIndex) {
    if (rows.length <= 1) return this;
    final nextRows = [...rows]..removeAt(rowIndex);
    return copyWith(
      rows: _repairGroups(nextRows),
      selectedRow: rowIndex < selectedRow
          ? selectedRow - 1
          : selectedRow.clamp(0, nextRows.length - 1),
    );
  }

  SmartGridDocument addColumn() {
    if (columnCount >= maxColumns) return this;
    return SmartGridDocument(
      columnCount: columnCount + 1,
      selectedRow: selectedRow,
      selectedColumn: selectedColumn,
      horizontalOffset: horizontalOffset,
      verticalOffset: verticalOffset,
      rows: [
        for (final row in rows) row.copyWith(cells: [...row.cells, '']),
      ],
    );
  }

  SmartGridDocument insertColumn(int index) {
    if (columnCount >= maxColumns) return this;
    final safeIndex = index.clamp(0, columnCount);
    return SmartGridDocument(
      columnCount: columnCount + 1,
      selectedRow: selectedRow,
      selectedColumn:
          safeIndex <= selectedColumn ? selectedColumn + 1 : selectedColumn,
      horizontalOffset: horizontalOffset,
      verticalOffset: verticalOffset,
      rows: [
        for (final row in rows)
          row.copyWith(cells: [...row.cells]..insert(safeIndex, '')),
      ],
    );
  }

  SmartGridDocument deleteColumn(int columnIndex) {
    if (columnCount <= 1) return this;
    return SmartGridDocument(
      columnCount: columnCount - 1,
      selectedRow: selectedRow,
      selectedColumn: columnIndex < selectedColumn
          ? selectedColumn - 1
          : selectedColumn.clamp(0, columnCount - 2),
      horizontalOffset: horizontalOffset,
      verticalOffset: verticalOffset,
      rows: [
        for (final row in rows)
          row.copyWith(cells: [...row.cells]..removeAt(columnIndex)),
      ],
    );
  }

  /// Applies one cell-level insert/delete operation.
  ///
  /// Returns `null` when preserving the shifted edge value would exceed the
  /// document's maximum row or column count.
  SmartGridDocument? applyCellOperation(
    int rowIndex,
    int columnIndex,
    SmartGridCellOperation operation,
  ) {
    if (rowIndex < 0 ||
        rowIndex >= rows.length ||
        columnIndex < 0 ||
        columnIndex >= columnCount) {
      return this;
    }
    return switch (operation) {
      SmartGridCellOperation.insertRowRight =>
        _insertCellInRow(rowIndex, columnIndex),
      SmartGridCellOperation.insertSameTypeDown =>
        _insertCellDown(rowIndex, columnIndex, sameTypeOnly: true),
      SmartGridCellOperation.insertAllRowsDown =>
        _insertCellDown(rowIndex, columnIndex, sameTypeOnly: false),
      SmartGridCellOperation.deleteRowLeft =>
        _deleteCellInRow(rowIndex, columnIndex),
      SmartGridCellOperation.deleteSameTypeUp =>
        _deleteCellUp(rowIndex, columnIndex, sameTypeOnly: true),
      SmartGridCellOperation.deleteAllRowsUp =>
        _deleteCellUp(rowIndex, columnIndex, sameTypeOnly: false),
    };
  }

  SmartGridDocument? _insertCellInRow(int rowIndex, int columnIndex) {
    var next = this;
    if (next.rows[rowIndex].cells.last.isNotEmpty) {
      if (next.columnCount >= maxColumns) return null;
      next = next.addColumn();
    }
    final rows = [...next.rows];
    final cells = [...rows[rowIndex].cells]..insert(columnIndex, '');
    cells.removeLast();
    rows[rowIndex] = rows[rowIndex].copyWith(cells: cells);
    return next._withRows(rows,
        selectedRow: rowIndex, selectedColumn: columnIndex);
  }

  SmartGridDocument? _insertCellDown(
    int rowIndex,
    int columnIndex, {
    required bool sameTypeOnly,
  }) {
    var next = this;
    var affected =
        next._affectedRowsBelow(rowIndex, sameTypeOnly: sameTypeOnly);
    if (next.rows[affected.last].cells[columnIndex].isNotEmpty) {
      if (next.rows.length >= maxRows) return null;
      final type = sameTypeOnly
          ? next.rows[rowIndex].type
          : next.rows[affected.last].type;
      next = next._appendRow(type);
      affected = next._affectedRowsBelow(rowIndex, sameTypeOnly: sameTypeOnly);
    }

    final rows = [...next.rows];
    for (var index = affected.length - 1; index > 0; index--) {
      final source = affected[index - 1];
      final target = affected[index];
      rows[target] = _replaceCell(
        rows[target],
        columnIndex,
        rows[source].cells[columnIndex],
      );
    }
    rows[rowIndex] = _replaceCell(rows[rowIndex], columnIndex, '');
    return next._withRows(rows,
        selectedRow: rowIndex, selectedColumn: columnIndex);
  }

  SmartGridDocument _deleteCellInRow(int rowIndex, int columnIndex) {
    final rows = [...this.rows];
    final cells = [...rows[rowIndex].cells];
    for (var column = columnIndex; column < cells.length - 1; column++) {
      cells[column] = cells[column + 1];
    }
    cells[cells.length - 1] = '';
    rows[rowIndex] = rows[rowIndex].copyWith(cells: cells);
    return _withRows(rows, selectedRow: rowIndex, selectedColumn: columnIndex);
  }

  SmartGridDocument _deleteCellUp(
    int rowIndex,
    int columnIndex, {
    required bool sameTypeOnly,
  }) {
    final affected = _affectedRowsBelow(rowIndex, sameTypeOnly: sameTypeOnly);
    final rows = [...this.rows];
    for (var index = 0; index < affected.length - 1; index++) {
      final target = affected[index];
      final source = affected[index + 1];
      rows[target] = _replaceCell(
        rows[target],
        columnIndex,
        rows[source].cells[columnIndex],
      );
    }
    final last = affected.last;
    rows[last] = _replaceCell(rows[last], columnIndex, '');
    return _withRows(rows, selectedRow: rowIndex, selectedColumn: columnIndex);
  }

  List<int> _affectedRowsBelow(int rowIndex, {required bool sameTypeOnly}) {
    final type = rows[rowIndex].type;
    return [
      for (var index = rowIndex; index < rows.length; index++)
        if (!sameTypeOnly || rows[index].type == type) index,
    ];
  }

  SmartGridDocument _appendRow(SmartGridRowType type) {
    final serial = DateTime.now().microsecondsSinceEpoch;
    final row = SmartGridRow(
      id: 'row-$serial-${rows.length + 1}',
      groupId:
          type == SmartGridRowType.score ? 'group-$serial' : 'lyrics-$serial',
      type: type,
      cells: List.filled(columnCount, ''),
    );
    return _withRows([...rows, row], repairGroups: true);
  }

  SmartGridDocument _withRows(
    List<SmartGridRow> rows, {
    int? selectedRow,
    int? selectedColumn,
    bool repairGroups = false,
  }) {
    return SmartGridDocument(
      rows: List.unmodifiable(repairGroups ? _repairGroups(rows) : rows),
      columnCount: columnCount,
      selectedRow: selectedRow ?? this.selectedRow,
      selectedColumn: selectedColumn ?? this.selectedColumn,
      horizontalOffset: horizontalOffset,
      verticalOffset: verticalOffset,
    );
  }

  SmartGridDocument ensureSize(int requiredRows, int requiredColumns) {
    var next = this;
    while (next.rows.length < requiredRows && next.rows.length < maxRows) {
      next = next.addRow();
    }
    while (
        next.columnCount < requiredColumns && next.columnCount < maxColumns) {
      next = next.addColumn();
    }
    return next;
  }

  SmartGridDocument reorderGroup(int oldRowIndex, int newRowIndex) {
    if (oldRowIndex < 0 || oldRowIndex >= rows.length) return this;
    final groupId = rows[oldRowIndex].groupId;
    final moving = rows.where((row) => row.groupId == groupId).toList();
    final remaining = rows.where((row) => row.groupId != groupId).toList();
    final selectedId = rows[selectedRow.clamp(0, rows.length - 1)].id;
    final beforeTarget = rows
        .take(newRowIndex.clamp(0, rows.length))
        .where((row) => row.groupId != groupId)
        .length;
    remaining.insertAll(beforeTarget.clamp(0, remaining.length), moving);
    return copyWith(
      rows: remaining,
      selectedRow: remaining.indexWhere((row) => row.id == selectedId),
    );
  }

  SmartGridDocument copyWith({
    List<SmartGridRow>? rows,
    int? columnCount,
    int? selectedRow,
    int? selectedColumn,
    double? horizontalOffset,
    double? verticalOffset,
  }) {
    return SmartGridDocument(
      rows: List.unmodifiable(rows ?? this.rows),
      columnCount: columnCount ?? this.columnCount,
      selectedRow: selectedRow ?? this.selectedRow,
      selectedColumn: selectedColumn ?? this.selectedColumn,
      horizontalOffset: horizontalOffset ?? this.horizontalOffset,
      verticalOffset: verticalOffset ?? this.verticalOffset,
    );
  }

  Map<String, Object?> toJson() => {
        'version': jsonVersion,
        'columnCount': columnCount,
        'selectedRow': selectedRow,
        'selectedColumn': selectedColumn,
        'horizontalOffset': horizontalOffset,
        'verticalOffset': verticalOffset,
        'rows': rows.map((row) => row.toJson()).toList(),
      };

  static SmartGridDocument? fromJson(Object? value) {
    if (value is! Map ||
        value['version'] != jsonVersion ||
        value['columnCount'] is! int ||
        value['rows'] is! List) {
      return null;
    }
    final columnCount = value['columnCount'] as int;
    if (columnCount < 1 || columnCount > maxColumns) return null;
    final rows = <SmartGridRow>[];
    for (final rawRow in value['rows'] as List) {
      final row = SmartGridRow.fromJson(rawRow);
      if (row == null || row.cells.length != columnCount) return null;
      rows.add(row);
    }
    if (rows.isEmpty || rows.length > maxRows) return null;
    final selectedRow = value['selectedRow'];
    final selectedColumn = value['selectedColumn'];
    final horizontalOffset = value['horizontalOffset'];
    final verticalOffset = value['verticalOffset'];
    return SmartGridDocument(
      rows: List.unmodifiable(_repairGroups(rows)),
      columnCount: columnCount,
      selectedRow:
          selectedRow is int ? selectedRow.clamp(0, rows.length - 1) : 0,
      selectedColumn:
          selectedColumn is int ? selectedColumn.clamp(0, columnCount - 1) : 0,
      horizontalOffset: horizontalOffset is num
          ? horizontalOffset.toDouble().clamp(0, double.infinity)
          : 0,
      verticalOffset: verticalOffset is num
          ? verticalOffset.toDouble().clamp(0, double.infinity)
          : 0,
    );
  }
}

SmartGridRow _replaceCell(SmartGridRow row, int column, String value) {
  final cells = [...row.cells];
  cells[column] = value;
  return row.copyWith(cells: cells);
}

List<SmartGridRow> _repairGroups(List<SmartGridRow> rows) {
  final unpairedScoreGroups = <String>[];
  final usedScoreGroups = <String>{};
  return List.generate(rows.length, (index) {
    final row = rows[index];
    if (row.type == SmartGridRowType.score) {
      var group = row.groupId.isEmpty ? 'group-${row.id}' : row.groupId;
      if (!usedScoreGroups.add(group)) {
        group = 'group-${row.id}';
        usedScoreGroups.add(group);
      }
      unpairedScoreGroups.add(group);
      return row.copyWith(groupId: group);
    }
    final group = unpairedScoreGroups.isNotEmpty
        ? unpairedScoreGroups.removeLast()
        : 'lyrics-${row.id}';
    return row.copyWith(groupId: group);
  });
}

String smartGridColumnLabel(int zeroBased) {
  var value = zeroBased + 1;
  final buffer = StringBuffer();
  while (value > 0) {
    value--;
    buffer.writeCharCode(65 + value % 26);
    value ~/= 26;
  }
  return buffer.toString().split('').reversed.join();
}

extension<T> on Iterable<T> {
  T? get firstOrNull {
    final iterator = this.iterator;
    return iterator.moveNext() ? iterator.current : null;
  }
}
