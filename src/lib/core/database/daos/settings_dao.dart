import 'package:drift/drift.dart';
import 'package:flutter/material.dart' show ThemeMode;

import '../app_database.dart';
import '../tables/settings_table.dart';

part 'settings_dao.g.dart';

@DriftAccessor(tables: [Settings])
class SettingsDao extends DatabaseAccessor<AppDatabase>
    with _$SettingsDaoMixin {
  SettingsDao(super.attachedDatabase);

  /// The row is created by the migration's `onCreate`, so it always exists.
  Stream<ThemeMode> watchThemeMode() =>
      (select(settings)..where((t) => t.id.equals(1)))
          .map((row) => row.themeMode)
          .watchSingle();

  Future<void> setThemeMode(ThemeMode mode) =>
      (update(settings)..where((t) => t.id.equals(1))).write(
        SettingsCompanion(themeMode: Value(mode)),
      );
}
