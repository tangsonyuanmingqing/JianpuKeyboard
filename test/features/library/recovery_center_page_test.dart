import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jianpu_keyboard/features/converter/converter_input.dart';
import 'package:jianpu_keyboard/features/library/recovery_center_page.dart';
import 'package:jianpu_keyboard/features/library/song_library_persistence.dart';
import 'package:jianpu_keyboard/features/library/song_library_providers.dart';
import 'package:jianpu_keyboard/features/library/song_record.dart';
import 'package:jianpu_keyboard/infrastructure/recovery_providers.dart';
import 'package:jianpu_keyboard/infrastructure/recovery_snapshot_repository.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('creates, previews, restores and deletes library snapshots',
      (tester) async {
    final savedSong = SongRecord(
      id: 'song-1',
      title: '晨光',
      input: const ConverterInput(scoreText: '3', lyricsText: '晨'),
      createdAt: DateTime.utc(2026, 9, 25),
      updatedAt: DateTime.utc(2026, 9, 25),
    );
    final repository = _SnapshotRepositoryFake([
      RecoverySnapshot(
        id: 'one',
        type: RecoverySnapshotType.library,
        createdAt: DateTime.utc(2026, 9, 25, 8),
        source: RecoverySnapshotSource.manual,
        note: '修改副歌前',
        payload: jsonDecode(
          SongLibraryPersistence.encodeDocument([savedSong]),
        ),
      ),
    ]);
    final container = ProviderContainer(overrides: [
      recoverySnapshotRepositoryProvider.overrideWithValue(repository),
      songLibraryPersistenceProvider.overrideWithValue(
        SongLibraryPersistence(preferences: _PreferencesFake()),
      ),
    ]);
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: RecoveryCenterPage()),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('修改副歌前'), findsOneWidget);

    await tester.tap(find.byTooltip('预览'));
    await tester.pumpAndSettle();
    expect(find.text('快照预览'), findsOneWidget);
    await tester.tap(find.text('关闭'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('创建快照'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '手动检查点');
    await tester.tap(find.text('创建'));
    await tester.pumpAndSettle();
    expect(repository.items, hasLength(2));
    expect(find.text('手动检查点'), findsOneWidget);

    await tester.tap(find.byTooltip('恢复').last);
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, '恢复'));
    await tester.pumpAndSettle();
    expect(container.read(songLibraryProvider).single.title, '晨光');

    final manualSnapshotCard = find.ancestor(
      of: find.text('手动检查点'),
      matching: find.byType(Card),
    );
    await tester.tap(
      find.descendant(
        of: manualSnapshotCard,
        matching: find.byTooltip('删除'),
      ),
    );
    await tester.pumpAndSettle();
    expect(repository.items, hasLength(2));
    expect(find.text('手动检查点'), findsNothing);
  });
}

class _SnapshotRepositoryFake extends RecoverySnapshotRepository {
  _SnapshotRepositoryFake(this.items);

  final List<RecoverySnapshot> items;

  @override
  Future<List<RecoverySnapshot>> list(RecoverySnapshotType type) async =>
      items.where((snapshot) => snapshot.type == type).toList();

  @override
  Future<RecoverySnapshot?> create({
    required RecoverySnapshotType type,
    required Object? payload,
    required RecoverySnapshotSource source,
    String? note,
    bool deduplicate = false,
  }) async {
    final snapshot = RecoverySnapshot(
      id: 'snapshot-${items.length}',
      type: type,
      createdAt: DateTime.utc(2026, 9, 25, 9, items.length),
      source: source,
      payload: payload,
      note: note,
    );
    items.insert(0, snapshot);
    return snapshot;
  }

  @override
  Future<void> delete(RecoverySnapshot snapshot) async {
    items.removeWhere((item) => item.id == snapshot.id);
  }
}

class _PreferencesFake extends Fake implements SharedPreferencesAsync {
  final Map<String, String> values = {};

  @override
  Future<void> setString(String key, String value) async {
    values[key] = value;
  }
}
