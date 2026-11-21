import 'package:drift/drift.dart';
import 'package:material_ui/material_ui.dart' show ThemeMode;

/// Single-row table (id = 1).
@DataClassName('SettingsRow')
class Settings extends Table {
  IntColumn get id => integer().withDefault(const Constant(1))();
  TextColumn get themeMode =>
      textEnum<ThemeMode>().withDefault(Constant(ThemeMode.system.name))();

  @override
  Set<Column> get primaryKey => {id};
}
