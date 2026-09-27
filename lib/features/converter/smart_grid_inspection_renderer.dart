import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../app/theme/app_typography.dart';
import 'smart_grid_converter.dart';
import 'smart_grid_document.dart';

class SmartGridInspectionRenderer {
  static const _cellWidth = 62.0;
  static const _cellHeight = 48.0;
  static const _rowHeaderWidth = 110.0;
  static const _columnHeaderHeight = 38.0;
  static const _titleHeight = 52.0;
  static const _maxImageDimension = 16000;
  static const _maxImagePixels = 80000000;

  const SmartGridInspectionRenderer();

  Future<Uint8List> render(
      SmartGridDocument document, SmartGridConversion conversion,
      {String songTitle = ''}) async {
    final rowCount = _visibleRowCount(document, conversion);
    final columnCount = _visibleColumnCount(document, conversion);
    final normalizedTitle = songTitle.trim();
    final titleHeight = normalizedTitle.isEmpty ? 0.0 : _titleHeight;
    final width = (_rowHeaderWidth + columnCount * _cellWidth).ceil();
    final height =
        (titleHeight + _columnHeaderHeight + rowCount * _cellHeight).ceil();
    if (width > _maxImageDimension ||
        height > _maxImageDimension ||
        width * height > _maxImagePixels) {
      throw const FormatException('表格范围过大，无法生成单张检查图。');
    }

    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    canvas.drawRect(
      Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()),
      Paint()..color = const Color(0xfffbf9ff),
    );

    if (normalizedTitle.isNotEmpty) {
      _paintTitle(canvas, normalizedTitle, width.toDouble(), titleHeight);
    }

    _paintCell(
      canvas,
      Rect.fromLTWH(0, titleHeight, _rowHeaderWidth, _columnHeaderHeight),
      '行 / 类型',
      background: const Color(0xffe8e8ef),
      bold: true,
    );
    for (var column = 0; column < columnCount; column++) {
      _paintCell(
        canvas,
        Rect.fromLTWH(
          _rowHeaderWidth + column * _cellWidth,
          titleHeight,
          _cellWidth,
          _columnHeaderHeight,
        ),
        smartGridColumnLabel(column),
        background: const Color(0xffe8e8ef),
        bold: true,
      );
    }

    for (var row = 0; row < rowCount; row++) {
      final sourceRow = document.rows[row];
      final groupNumber = _groupNumber(document, sourceRow.groupId);
      final tint = groupNumber.isEven
          ? const Color(0xfff1eaf9)
          : const Color(0xffeaf0fb);
      final top = titleHeight + _columnHeaderHeight + row * _cellHeight;
      _paintCell(
        canvas,
        Rect.fromLTWH(0, top, _rowHeaderWidth, _cellHeight),
        '${row + 1}  ${sourceRow.type == SmartGridRowType.score ? '谱' : '词'} · $groupNumber',
        background: tint,
        bold: true,
      );
      for (var column = 0; column < columnCount; column++) {
        final issue = conversion.issues
            .where((item) => item.row == row && item.column == column)
            .firstOrNull;
        final background = issue?.severity == SmartGridIssueSeverity.error
            ? const Color(0xffffd9df)
            : issue != null
                ? const Color(0xffffedb3)
                : tint;
        final value = row < conversion.outputRows.length &&
                column < conversion.outputRows[row].length
            ? conversion.outputRows[row][column]
            : '';
        _paintCell(
          canvas,
          Rect.fromLTWH(
            _rowHeaderWidth + column * _cellWidth,
            top,
            _cellWidth,
            _cellHeight,
          ),
          issue == null ? value : '$value${value.isEmpty ? '' : ' '}!',
          background: background,
        );
      }
    }

    final picture = recorder.endRecording();
    final image = await picture.toImage(width, height);
    picture.dispose();
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    if (bytes == null) throw StateError('无法生成检查图。');
    return bytes.buffer.asUint8List();
  }

  int _visibleRowCount(
    SmartGridDocument document,
    SmartGridConversion conversion,
  ) {
    var last = document.rows.lastIndexWhere(
      (row) => row.cells.any((cell) => cell.isNotEmpty),
    );
    for (final issue in conversion.issues) {
      if (issue.row > last) last = issue.row;
    }
    return (last + 1).clamp(1, document.rows.length);
  }

  int _visibleColumnCount(
    SmartGridDocument document,
    SmartGridConversion conversion,
  ) {
    var last = 0;
    for (final row in document.rows) {
      final rowLast = row.cells.lastIndexWhere((cell) => cell.isNotEmpty);
      if (rowLast > last) last = rowLast;
    }
    for (final issue in conversion.issues) {
      if (issue.column > last) last = issue.column;
    }
    return (last + 1).clamp(1, document.columnCount);
  }

  int _groupNumber(SmartGridDocument document, String groupId) {
    final groups = <String>[];
    for (final row in document.rows) {
      if (row.type == SmartGridRowType.score && !groups.contains(row.groupId)) {
        groups.add(row.groupId);
      }
    }
    final index = groups.indexOf(groupId);
    return index < 0 ? 0 : index + 1;
  }

  void _paintCell(
    Canvas canvas,
    Rect rect,
    String text, {
    required Color background,
    bool bold = false,
  }) {
    canvas.drawRect(rect, Paint()..color = background);
    canvas.drawRect(
      rect,
      Paint()
        ..color = const Color(0xff8c8c96)
        ..style = PaintingStyle.stroke,
    );
    const typography = AppTypography.standard();
    final painter = TextPainter(
      text: TextSpan(
        text: text,
        style: (bold ? typography.inspectionHeader : typography.inspectionCell)
            .copyWith(color: const Color(0xff202027)),
      ),
      textDirection: TextDirection.ltr,
      maxLines: 1,
      ellipsis: '…',
      textAlign: TextAlign.center,
    )..layout(maxWidth: rect.width - 6);
    painter.paint(
      canvas,
      Offset(
        rect.left + (rect.width - painter.width) / 2,
        rect.top + (rect.height - painter.height) / 2,
      ),
    );
  }

  void _paintTitle(Canvas canvas, String title, double width, double height) {
    const typography = AppTypography.standard();
    final painter = TextPainter(
      text: TextSpan(
        text: title,
        style: typography.inspectionTitle.copyWith(
          color: const Color(0xff202027),
        ),
      ),
      textDirection: TextDirection.ltr,
      maxLines: 1,
      ellipsis: '…',
      textAlign: TextAlign.center,
    )..layout(maxWidth: width - 24);
    painter.paint(
      canvas,
      Offset((width - painter.width) / 2, (height - painter.height) / 2),
    );
  }
}

extension<T> on Iterable<T> {
  T? get firstOrNull {
    final iterator = this.iterator;
    return iterator.moveNext() ? iterator.current : null;
  }
}
