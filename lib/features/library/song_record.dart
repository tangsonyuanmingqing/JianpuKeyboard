import '../../core/mapping/keyboard_mapping.dart';
import '../converter/converter_input.dart';
import '../converter/smart_grid_document.dart';

/// A named, locally stored song draft.  Its source is always retained even
/// when conversion produced errors.
class SongRecord {
  final String id;
  final String title;
  final String artist;
  final List<String> tags;
  final String notes;
  final ConverterInput input;
  final SmartGridDocument? gridDocument;
  final String editorMode;
  final SongResultSnapshot? result;
  final bool resultIsStale;
  final DateTime createdAt;
  final DateTime updatedAt;

  const SongRecord({
    required this.id,
    required this.title,
    this.artist = '',
    this.tags = const [],
    this.notes = '',
    required this.input,
    this.gridDocument,
    this.editorMode = 'text',
    this.result,
    this.resultIsStale = false,
    required this.createdAt,
    required this.updatedAt,
  });

  SongRecord copyWith({
    String? title,
    String? artist,
    List<String>? tags,
    String? notes,
    ConverterInput? input,
    SmartGridDocument? gridDocument,
    String? editorMode,
    SongResultSnapshot? result,
    bool? resultIsStale,
    bool clearResult = false,
    DateTime? updatedAt,
  }) =>
      SongRecord(
        id: id,
        title: title ?? this.title,
        artist: artist ?? this.artist,
        tags: tags ?? this.tags,
        notes: notes ?? this.notes,
        input: input ?? this.input,
        gridDocument: gridDocument ?? this.gridDocument,
        editorMode: editorMode ?? this.editorMode,
        result: clearResult ? null : result ?? this.result,
        resultIsStale:
            clearResult ? false : resultIsStale ?? this.resultIsStale,
        createdAt: createdAt,
        updatedAt: updatedAt ?? this.updatedAt,
      );

  Map<String, Object?> toJson() => {
        'id': id,
        'title': title,
        'artist': artist,
        'tags': tags,
        'notes': notes,
        'scoreText': input.scoreText,
        'lyricsText': input.lyricsText,
        'gridDocument': gridDocument?.toJson(),
        'editorMode': editorMode,
        'result': result?.toJson(),
        'resultIsStale': resultIsStale,
        'createdAt': createdAt.toUtc().toIso8601String(),
        'updatedAt': updatedAt.toUtc().toIso8601String(),
      };

  static SongRecord? fromJson(Object? value) {
    if (value is! Map) return null;
    String? string(String key, {bool required = false}) {
      final item = value[key];
      if (item is String) return item;
      return required ? null : '';
    }

    final id = string('id', required: true);
    final title = string('title', required: true);
    final scoreText = string('scoreText', required: true);
    final lyricsText = string('lyricsText', required: true);
    final createdAt =
        DateTime.tryParse(string('createdAt', required: true) ?? '');
    final updatedAt =
        DateTime.tryParse(string('updatedAt', required: true) ?? '');
    final rawTags = value['tags'];
    if (id == null ||
        title == null ||
        title.trim().isEmpty ||
        scoreText == null ||
        lyricsText == null ||
        createdAt == null ||
        updatedAt == null ||
        rawTags is! List ||
        rawTags.any((item) => item is! String)) {
      return null;
    }
    final rawResult = value['result'];
    final result =
        rawResult == null ? null : SongResultSnapshot.fromJson(rawResult);
    if (rawResult != null && result == null) return null;
    final rawGrid = value['gridDocument'];
    final gridDocument =
        rawGrid == null ? null : SmartGridDocument.fromJson(rawGrid);
    if (rawGrid != null && gridDocument == null) return null;
    return SongRecord(
      id: id,
      title: title,
      artist: string('artist') ?? '',
      tags: List<String>.unmodifiable(rawTags.cast<String>()),
      notes: string('notes') ?? '',
      input: ConverterInput(scoreText: scoreText, lyricsText: lyricsText),
      gridDocument: gridDocument,
      editorMode: value['editorMode'] == 'grid' ? 'grid' : 'text',
      result: result,
      resultIsStale: value['resultIsStale'] == true ||
          (result != null && !result.usesCurrentOutputFormat),
      createdAt: createdAt.toUtc(),
      updatedAt: updatedAt.toUtc(),
    );
  }
}

class SongResultSnapshot {
  static const currentOutputFormatVersion = 2;

  final String output;
  final Map<String, Object?> mapping;
  final List<String> warnings;
  final DateTime savedAt;
  final int outputFormatVersion;

  const SongResultSnapshot(
      {required this.output,
      required this.mapping,
      required this.warnings,
      required this.savedAt,
      this.outputFormatVersion = currentOutputFormatVersion});

  bool get usesCurrentOutputFormat =>
      outputFormatVersion == currentOutputFormatVersion;

  Map<String, Object?> toJson() => {
        'output': output,
        'mapping': mapping,
        'warnings': warnings,
        'savedAt': savedAt.toUtc().toIso8601String(),
        'outputFormatVersion': outputFormatVersion,
      };

  static SongResultSnapshot? fromJson(Object? value) {
    if (value is! Map ||
        value['output'] is! String ||
        value['mapping'] is! Map ||
        value['warnings'] is! List ||
        (value['warnings'] as List).any((item) => item is! String) ||
        value['savedAt'] is! String) {
      return null;
    }
    final mapping = <String, Object?>{};
    for (final entry in (value['mapping'] as Map).entries) {
      if (entry.key is! String) return null;
      mapping[entry.key as String] = entry.value;
    }
    if (!KeyboardMapping.fromJson(mapping).isValid) return null;
    final savedAt = DateTime.tryParse(value['savedAt'] as String);
    if (savedAt == null) return null;
    final rawFormatVersion = value['outputFormatVersion'];
    if (rawFormatVersion != null && rawFormatVersion is! int) {
      return null;
    }
    return SongResultSnapshot(
        output: value['output'] as String,
        mapping: Map.unmodifiable(mapping),
        warnings: List<String>.unmodifiable(
            (value['warnings'] as List).cast<String>()),
        savedAt: savedAt.toUtc(),
        outputFormatVersion: rawFormatVersion as int? ?? 1);
  }
}
