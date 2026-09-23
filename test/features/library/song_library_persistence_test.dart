import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:jianpu_keyboard/core/mapping/keyboard_mapping.dart';
import 'package:jianpu_keyboard/features/converter/converter_input.dart';
import 'package:jianpu_keyboard/features/converter/smart_grid_document.dart';
import 'package:jianpu_keyboard/features/library/song_library_persistence.dart';
import 'package:jianpu_keyboard/features/library/song_record.dart';

void main() {
  SongRecord song() {
    final now = DateTime.utc(2026, 9, 23);
    return SongRecord(
      id: 'song-1',
      title: '晨光',
      artist: '测试歌手',
      tags: const ['练习', '原创'],
      notes: '第一版',
      input: const ConverterInput(scoreText: '3 4 5', lyricsText: '晨 光'),
      gridDocument:
          SmartGridDocument.empty(rows: 2, columns: 3).setCell(0, 0, '3'),
      editorMode: 'grid',
      result: SongResultSnapshot(
        output: 'D F G',
        mapping: const KeyboardMapping().toJson(),
        warnings: const ['歌词数量多于对应的音符。'],
        savedAt: now,
      ),
      createdAt: now,
      updatedAt: now,
    );
  }

  test('backup round trip retains source, metadata and result snapshot', () {
    final decoded = SongLibraryPersistence.decodeDocument(
      SongLibraryPersistence.encodeDocument([song()]),
    );
    expect(decoded, hasLength(1));
    expect(decoded.single.title, '晨光');
    expect(decoded.single.input.lyricsText, '晨 光');
    expect(decoded.single.result!.output, 'D F G');
    expect(decoded.single.result!.warnings, hasLength(1));
    expect(decoded.single.editorMode, 'grid');
    expect(decoded.single.gridDocument!.rows[0].cells[0], '3');
  });

  test('version 1 backup remains importable as text mode', () {
    final legacySong = Map<String, Object?>.from(song().toJson())
      ..remove('gridDocument')
      ..remove('editorMode');
    final decoded = SongLibraryPersistence.decodeDocument(
      jsonEncode({
        'version': 1,
        'songs': [legacySong]
      }),
    );

    expect(decoded.single.editorMode, 'text');
    expect(decoded.single.gridDocument, isNull);
  });

  test('damaged or unsupported backup is rejected before import', () {
    expect(
      () => SongLibraryPersistence.decodeDocument('{"version":3,"songs":[]}'),
      throwsFormatException,
    );
    expect(
      () => SongLibraryPersistence.decodeDocument('{"version":1,"songs":[{}]}'),
      throwsFormatException,
    );
  });
}
