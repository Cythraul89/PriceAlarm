import 'package:drift/drift.dart';

import '../decimal_converter.dart';

@DataClassName('ItemRow')
class Items extends Table {
  TextColumn get id => text()();
  TextColumn get name => text()();
  TextColumn get targetPrice => text().map(const DecimalConverter())();
  TextColumn get currency => text().withDefault(const Constant('CHF'))();

  // Local wall-clock time of the daily check, in minutes since midnight
  // (0–1439). 480 = 08:00.
  IntColumn get checkTime => integer().withDefault(const Constant(480))();
  BoolColumn get enabled => boolean().withDefault(const Constant(true))();

  // True while the last check found bestPrice <= targetPrice (display).
  BoolColumn get alarmActive => boolean().withDefault(const Constant(false))();

  // When the alarm last rang (UTC). The alarm rings at most once per daily
  // cycle (REQUIREMENTS 5.2); added in schema version 2.
  DateTimeColumn get lastAlarmAt => dateTime().nullable()();
  DateTimeColumn get lastRunAt => dateTime().nullable()();
  DateTimeColumn get createdAt => dateTime()();

  @override
  Set<Column> get primaryKey => {id};
}
