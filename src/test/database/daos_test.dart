import 'package:decimal/decimal.dart';
import 'package:drift/native.dart';
import 'package:material_ui/material_ui.dart' show ThemeMode;
import 'package:flutter_test/flutter_test.dart';
import 'package:price_alarm/core/database/app_database.dart';
import 'package:price_alarm/core/models/check_outcome.dart';
import 'package:price_alarm/core/models/enums.dart';
import 'package:price_alarm/core/models/item_draft.dart';

ItemDraft _draft({
  String? id,
  String target = '2000',
  List<OfferDraft>? offers,
}) => ItemDraft(
  id: id,
  name: 'ASUS Radeon AI PRO R9700',
  targetPrice: Decimal.parse(target),
  checkTime: 480,
  enabled: true,
  offers:
      offers ??
      const [
        OfferDraft(
          url: 'https://www.brack.ch/r9700',
          shopName: 'Brack',
          fetchMode: FetchMode.auto,
        ),
        OfferDraft(
          url: 'https://www.galaxus.ch/r9700',
          shopName: 'Galaxus',
          fetchMode: FetchMode.auto,
        ),
      ],
);

final _okOutcome = CheckOutcome(
  status: CheckStatus.ok,
  method: FetchMethod.webview,
  price: Decimal.parse('2209.00'),
  currency: 'CHF',
  availability: 'OutOfStock',
);

void main() {
  late AppDatabase db;
  final now = DateTime.utc(2026, 11, 21, 8);

  setUp(() => db = AppDatabase.forTesting(NativeDatabase.memory()));
  tearDown(() => db.close());

  group('ItemsDao.saveDraft', () {
    test('creates the item with its offers', () async {
      final id = await db.itemsDao.saveDraft(_draft(), now: now);
      final item = await db.itemsDao.findById(id);
      final offers = await db.offersDao.getByItem(id);
      expect(item?.targetPrice, Decimal.parse('2000'));
      expect(item?.createdAt.isAtSameMomentAs(now), isTrue);
      expect(offers.map((o) => o.shopName), unorderedEquals(['Brack', 'Galaxus']));
    });

    test('changing the target price re-arms an active alarm', () async {
      final id = await db.itemsDao.saveDraft(_draft(), now: now);
      await db.itemsDao.recordRun(id, alarmActive: true, lastRunAt: now);
      final offers = await db.offersDao.getByItem(id);
      final keep = [
        for (final o in offers)
          OfferDraft(
            id: o.id,
            url: o.url,
            shopName: o.shopName,
            fetchMode: o.fetchMode,
          ),
      ];

      await db.itemsDao.saveDraft(
        _draft(id: id, target: '2000', offers: keep),
        now: now,
      );
      expect((await db.itemsDao.findById(id))?.alarmActive, isTrue);

      await db.itemsDao.saveDraft(
        _draft(id: id, target: '1900', offers: keep),
        now: now,
      );
      expect((await db.itemsDao.findById(id))?.alarmActive, isFalse);
    });

    test('a changed offer URL clears that offer\'s last-check data, '
        'removed offers are deleted', () async {
      final id = await db.itemsDao.saveDraft(_draft(), now: now);
      final offers = await db.offersDao.getByItem(id);
      final brack = offers.firstWhere((o) => o.shopName == 'Brack');
      await db.offersDao.recordCheck(
        brack.id,
        _okOutcome,
        checkedAt: now,
        rememberMethod: true,
      );

      await db.itemsDao.saveDraft(
        _draft(
          id: id,
          offers: [
            OfferDraft(
              id: brack.id,
              url: 'https://www.brack.ch/other',
              shopName: 'Brack',
              fetchMode: FetchMode.auto,
            ),
          ],
        ),
        now: now,
      );
      final after = await db.offersDao.getByItem(id);
      expect(after, hasLength(1));
      expect(after.single.lastPrice, isNull);
      expect(after.single.resolvedMethod, isNull);
      expect(after.single.lastStatus, isNull);
    });
  });

  group('OffersDao.recordCheck', () {
    test('stores price and remembers the method under auto', () async {
      final id = await db.itemsDao.saveDraft(_draft(), now: now);
      final offer = (await db.offersDao.getByItem(id)).first;
      await db.offersDao.recordCheck(
        offer.id,
        _okOutcome,
        checkedAt: now,
        rememberMethod: true,
      );
      final stored = (await db.offersDao.getByItem(id))
          .firstWhere((o) => o.id == offer.id);
      expect(stored.lastPrice, Decimal.parse('2209.00'));
      expect(stored.lastStatus, CheckStatus.ok);
      expect(stored.resolvedMethod, FetchMethod.webview);
      expect(stored.lastAvailability, 'OutOfStock');
    });

    test('a failed check keeps the last known price', () async {
      final id = await db.itemsDao.saveDraft(_draft(), now: now);
      final offer = (await db.offersDao.getByItem(id)).first;
      await db.offersDao.recordCheck(
        offer.id,
        _okOutcome,
        checkedAt: now,
        rememberMethod: true,
      );
      await db.offersDao.recordCheck(
        offer.id,
        const CheckOutcome(
          status: CheckStatus.blocked,
          method: FetchMethod.http,
          error: 'HTTP 403',
        ),
        checkedAt: now.add(const Duration(days: 1)),
        rememberMethod: true,
      );
      final stored = (await db.offersDao.getByItem(id))
          .firstWhere((o) => o.id == offer.id);
      expect(stored.lastPrice, Decimal.parse('2209.00'));
      expect(stored.lastStatus, CheckStatus.blocked);
      expect(stored.lastError, 'HTTP 403');
      // A failure must not overwrite the method that last worked.
      expect(stored.resolvedMethod, FetchMethod.webview);
    });
  });

  group('PriceChecksDao', () {
    test('history is newest first and joined with the shop name', () async {
      final id = await db.itemsDao.saveDraft(_draft(), now: now);
      final offer = (await db.offersDao.getByItem(id))
          .firstWhere((o) => o.shopName == 'Brack');
      await db.priceChecksDao.insertCheck(offer.id, _okOutcome, checkedAt: now);
      await db.priceChecksDao.insertCheck(
        offer.id,
        const CheckOutcome(status: CheckStatus.networkError, error: 'x'),
        checkedAt: now.add(const Duration(days: 1)),
      );
      final history = await db.priceChecksDao.watchByItem(id, limit: 10).first;
      expect(history.map((c) => c.status), [
        CheckStatus.networkError,
        CheckStatus.ok,
      ]);
      expect(history.first.shopName, 'Brack');
    });

    test('deleteOlderThan removes only entries before the cutoff', () async {
      final id = await db.itemsDao.saveDraft(_draft(), now: now);
      final offer = (await db.offersDao.getByItem(id)).first;
      await db.priceChecksDao.insertCheck(
        offer.id,
        _okOutcome,
        checkedAt: now.subtract(const Duration(days: 400)),
      );
      await db.priceChecksDao.insertCheck(offer.id, _okOutcome, checkedAt: now);
      final deleted = await db.priceChecksDao.deleteOlderThan(
        now.subtract(const Duration(days: 365)),
      );
      expect(deleted, 1);
    });

    test('deleting an item cascades to offers and history', () async {
      final id = await db.itemsDao.saveDraft(_draft(), now: now);
      final offer = (await db.offersDao.getByItem(id)).first;
      await db.priceChecksDao.insertCheck(offer.id, _okOutcome, checkedAt: now);
      await db.itemsDao.deleteById(id);
      expect(await db.offersDao.getByItem(id), isEmpty);
      expect(await db.select(db.priceChecks).get(), isEmpty);
    });
  });

  group('SettingsDao', () {
    test('the settings row exists after creation and defaults to system',
        () async {
      expect(await db.settingsDao.watchThemeMode().first, ThemeMode.system);
      await db.settingsDao.setThemeMode(ThemeMode.dark);
      expect(await db.settingsDao.watchThemeMode().first, ThemeMode.dark);
    });
  });

  group('AppDatabase export/import', () {
    test('round-trips all data', () async {
      final id = await db.itemsDao.saveDraft(_draft(), now: now);
      final offer = (await db.offersDao.getByItem(id)).first;
      await db.priceChecksDao.insertCheck(offer.id, _okOutcome, checkedAt: now);
      final exported = await db.exportAll();

      final other = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(other.close);
      final counts = await other.importAll(exported);
      expect(counts, (items: 1, offers: 2, checks: 1));
      expect((await other.itemsDao.findById(id))?.name, 'ASUS Radeon AI PRO R9700');
    });
  });
}
