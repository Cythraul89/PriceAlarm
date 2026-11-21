import 'dart:io';

import 'package:decimal/decimal.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:price_alarm/core/database/app_database.dart';

void main() {
  group('AppDatabase migration', () {
    test('upgrades a real schema-1 database to 2 and keeps its data', () async {
      // Written by the previous app version (see the fixture header).
      final dump = File(
        'test/fixtures/schema_v1_with_item.sql',
      ).readAsStringSync();
      final db = AppDatabase.forTesting(
        NativeDatabase.memory(
          setup: (raw) {
            for (final statement in dump.split(';\n')) {
              final sql = statement
                  .split('\n')
                  .where((l) => !l.startsWith('--'))
                  .join('\n')
                  .trim();
              if (sql.isNotEmpty) raw.execute(sql);
            }
          },
        ),
      );
      addTearDown(db.close);

      final items = await db.itemsDao.getAll();
      expect(items.single.name, 'radon');
      expect(items.single.targetPrice, Decimal.parse('3000'));
      expect(items.single.lastAlarmAt, isNull);
      expect(await db.offersDao.getByItem(items.single.id), hasLength(1));

      // The new column is usable after the upgrade.
      final rang = DateTime.utc(2026, 11, 22, 8);
      await db.itemsDao.recordRun(
        items.single.id,
        alarmActive: true,
        lastAlarmAt: rang,
      );
      final after = await db.itemsDao.findById(items.single.id);
      expect(after?.lastAlarmAt?.isAtSameMomentAs(rang), isTrue);

      final version = await db.customSelect('PRAGMA user_version').get();
      expect(version.single.data.values.first, 2);
    });

    test('imports a backup written before lastAlarmAt existed', () async {
      final db = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(db.close);
      // Shape of a schema-1 export: no lastAlarmAt key.
      final counts = await db.importAll({
        'items': [
          {
            'id': 'i1',
            'name': 'radon',
            'targetPrice': '3000',
            'currency': 'CHF',
            'checkTime': 1055,
            'enabled': true,
            'alarmActive': false,
            'lastRunAt': null,
            'createdAt': DateTime.utc(2026, 11, 21).millisecondsSinceEpoch,
          },
        ],
        'offers': <Map<String, dynamic>>[],
        'price_checks': <Map<String, dynamic>>[],
      });
      expect(counts.items, 1);
      expect((await db.itemsDao.findById('i1'))?.lastAlarmAt, isNull);
    });
  });
}
