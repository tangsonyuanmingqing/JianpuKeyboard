import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'recovery_snapshot_repository.dart';

final recoverySnapshotRepositoryProvider = Provider<RecoverySnapshotRepository>(
  (ref) => RecoverySnapshotRepository(),
);
