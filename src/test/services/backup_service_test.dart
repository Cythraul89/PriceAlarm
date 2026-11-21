import 'dart:typed_data';

import 'package:decimal/decimal.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:price_alarm/core/database/app_database.dart';
import 'package:price_alarm/core/models/check_outcome.dart';
import 'package:price_alarm/core/models/enums.dart';
import 'package:price_alarm/core/models/item_draft.dart';
import 'package:price_alarm/core/services/backup_service.dart';

void main() {
  group('BackupService', () {
    test('export → import round-trips through the real ZIP/JSON bytes', () async {
      final source = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(source.close);
      final now = DateTime.utc(2026, 11, 21, 8);
      final id = await source.itemsDao.saveDraft(
        ItemDraft(
          name: 'radon',
          targetPrice: _target,
          checkTime: 1055,
          enabled: true,
          offers: const [
            OfferDraft(
              url: 'https://www.brack.ch/x',
              shopName: 'Brack',
              fetchMode: FetchMode.auto,
            ),
          ],
        ),
        now: now,
      );
      final offer = (await source.offersDao.getByItem(id)).single;
      final outcome = CheckOutcome(
        status: CheckStatus.ok,
        method: FetchMethod.http,
        price: Decimal.parse('2209.00'),
        currency: 'CHF',
      );
      await source.offersDao.recordCheck(
        offer.id,
        outcome,
        checkedAt: now,
        rememberMethod: true,
      );
      await source.priceChecksDao.insertCheck(offer.id, outcome, checkedAt: now);
      await source.itemsDao.recordRun(id, alarmActive: true, lastAlarmAt: now);

      final Uint8List bytes = await BackupService(db: source).export();

      final target = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(target.close);
      final counts = await BackupService(db: target).import(bytes);
      expect(counts, (items: 1, offers: 1, checks: 1));

      final item = (await target.itemsDao.findById(id))!;
      expect(item.targetPrice, _target);
      expect(item.lastAlarmAt?.isAtSameMomentAs(now), isTrue);
      final restored = (await target.offersDao.getByItem(id)).single;
      expect(restored.lastPrice, Decimal.parse('2209.00'));
      expect(restored.resolvedMethod, FetchMethod.http);
      final history = await target.priceChecksDao.watchByItem(id, limit: 5).first;
      expect(history.single.price, Decimal.parse('2209.00'));
    });

    test('rejects a file that is not a backup', () async {
      final db = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(db.close);
      expect(
        () => BackupService(db: db).import(Uint8List.fromList([1, 2, 3])),
        throwsA(isA<FormatException>()),
      );
    });
  });
}

final _target = Decimal.parse('3000.00');
