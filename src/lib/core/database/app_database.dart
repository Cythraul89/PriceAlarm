import 'dart:io';

import 'package:decimal/decimal.dart';
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:material_ui/material_ui.dart' show ThemeMode;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../models/enums.dart';
import 'daos/items_dao.dart';
import 'daos/offers_dao.dart';
import 'daos/price_checks_dao.dart';
import 'daos/settings_dao.dart';
import 'decimal_converter.dart';
import 'tables/items_table.dart';
import 'tables/offers_table.dart';
import 'tables/price_checks_table.dart';
import 'tables/settings_table.dart';

part 'app_database.g.dart';

const kDatabaseFileName = 'price_alarm.sqlite';

@DriftDatabase(
  tables: [Items, Offers, PriceChecks, Settings],
  daos: [ItemsDao, OffersDao, PriceChecksDao, SettingsDao],
)
class AppDatabase extends _$AppDatabase {
  AppDatabase() : super(_openConnection());

  AppDatabase.forTesting(super.executor);

  /// For the Android background isolate, which has no access to the UI
  /// isolate's database instance. Opens the same file.
  AppDatabase.openForIsolate() : super(_openConnection());

  @override
  int get schemaVersion => 2;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (m) async {
      await m.createAll();
      await into(settings).insert(SettingsCompanion.insert());
    },
    onUpgrade: (m, from, to) async {
      if (from < 2) {
        await m.addColumn(items, items.lastAlarmAt);
      }
    },
    // Foreign keys are off by default in SQLite; cascade deletes of offers
    // and history depend on them.
    beforeOpen: (details) async {
      await customStatement('PRAGMA foreign_keys = ON');
      // The Android background isolate opens its own connection to the same
      // file; wait for a concurrent writer instead of failing with BUSY.
      await customStatement('PRAGMA busy_timeout = 5000');
    },
  );

  // ── Backup ─────────────────────────────────────────────────────────────────

  /// Every table as JSON-ready maps, read in one transaction so the
  /// snapshot is consistent.
  Future<Map<String, List<Map<String, Object?>>>> exportAll() =>
      transaction(() async {
        final itemRows = await select(items).get();
        final offerRows = await select(offers).get();
        final checkRows = await select(priceChecks).get();
        return {
          'items': [for (final r in itemRows) r.toJson()],
          'offers': [for (final r in offerRows) r.toJson()],
          'price_checks': [for (final r in checkRows) r.toJson()],
        };
      });

  /// Replaces all data with [data] (as produced by [exportAll]).
  Future<({int items, int offers, int checks})> importAll(
    Map<String, dynamic> data,
  ) => transaction(() async {
    await delete(items).go(); // cascades to offers and price_checks
    final itemList = (data['items'] as List).cast<Map<String, dynamic>>();
    final offerList = (data['offers'] as List).cast<Map<String, dynamic>>();
    final checkList = (data['price_checks'] as List)
        .cast<Map<String, dynamic>>();
    await batch((b) {
      b.insertAll(items, [for (final j in itemList) ItemRow.fromJson(j)]);
      b.insertAll(offers, [for (final j in offerList) OfferRow.fromJson(j)]);
      b.insertAll(priceChecks, [
        for (final j in checkList) PriceCheckRow.fromJson(j),
      ]);
    });
    return (
      items: itemList.length,
      offers: offerList.length,
      checks: checkList.length,
    );
  });
}

LazyDatabase _openConnection() => LazyDatabase(() async {
  final dir = await getApplicationSupportDirectory();
  final file = File(p.join(dir.path, kDatabaseFileName));
  // NativeDatabase on the calling isolate, not createInBackground(): keeps
  // the setup identical in the UI and the WorkManager isolate.
  return NativeDatabase(file);
});
