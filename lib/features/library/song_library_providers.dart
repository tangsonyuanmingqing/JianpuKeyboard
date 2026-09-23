import 'dart:math';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'song_library_persistence.dart';
import 'song_record.dart';

class SongLibraryNotifier extends Notifier<List<SongRecord>> {
  @override
  List<SongRecord> build() => ref.read(initialSongLibraryProvider);

  Future<void> saveRecord(SongRecord record) async {
    final index = state.indexWhere((item) => item.id == record.id);
    final next = [...state];
    if (index == -1) {
      next.add(record);
    } else {
      next[index] = record;
    }
    state = List.unmodifiable(next);
    await ref.read(songLibraryPersistenceProvider).save(state);
  }

  Future<void> delete(String id) async {
    state = List.unmodifiable(state.where((song) => song.id != id));
    await ref.read(songLibraryPersistenceProvider).save(state);
  }

  Future<void> replaceAll(List<SongRecord> songs) async {
    state = List.unmodifiable(songs);
    await ref.read(songLibraryPersistenceProvider).save(state);
  }
}

final songLibraryPersistenceProvider =
    Provider<SongLibraryPersistence>((ref) => SongLibraryPersistence());
final initialSongLibraryProvider =
    Provider<List<SongRecord>>((ref) => const []);
final songLibraryProvider =
    NotifierProvider<SongLibraryNotifier, List<SongRecord>>(
        SongLibraryNotifier.new);

String newSongId() =>
    '${DateTime.now().microsecondsSinceEpoch.toRadixString(36)}${Random.secure().nextInt(1 << 32).toRadixString(36)}';
