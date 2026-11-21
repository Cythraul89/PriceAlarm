import 'package:drift/drift.dart';

import '../../models/enums.dart';
import '../../models/offer.dart';
import '../../models/check_outcome.dart';
import '../app_database.dart';
import '../tables/offers_table.dart';

part 'offers_dao.g.dart';

@DriftAccessor(tables: [Offers])
class OffersDao extends DatabaseAccessor<AppDatabase> with _$OffersDaoMixin {
  OffersDao(super.attachedDatabase);

  Stream<List<Offer>> watchAll() =>
      (select(offers)..orderBy([(t) => OrderingTerm.asc(t.shopName)]))
          .map(offerFromRow)
          .watch();

  Stream<List<Offer>> watchByItem(String itemId) =>
      (select(offers)
            ..where((t) => t.itemId.equals(itemId))
            ..orderBy([(t) => OrderingTerm.asc(t.shopName)]))
          .map(offerFromRow)
          .watch();

  Future<List<Offer>> getByItem(String itemId) =>
      (select(offers)..where((t) => t.itemId.equals(itemId)))
          .map(offerFromRow)
          .get();

  /// Writes only the last-check columns. A failed check keeps the previous
  /// `lastPrice` so the UI can still show the last known price next to the
  /// failure; `lastStatus` says whether it is current.
  Future<void> recordCheck(
    String offerId,
    CheckOutcome outcome, {
    required DateTime checkedAt,
    required bool rememberMethod,
  }) {
    final ok = outcome.status == CheckStatus.ok;
    return (update(offers)..where((t) => t.id.equals(offerId))).write(
      OffersCompanion(
        lastStatus: Value(outcome.status),
        lastError: Value(outcome.error),
        lastCheckedAt: Value(checkedAt),
        lastPrice: ok ? Value(outcome.price) : const Value.absent(),
        lastCurrency: ok ? Value(outcome.currency) : const Value.absent(),
        lastAvailability: ok
            ? Value(outcome.availability)
            : const Value.absent(),
        resolvedMethod: rememberMethod && ok
            ? Value(outcome.method)
            : const Value.absent(),
      ),
    );
  }
}

Offer offerFromRow(OfferRow row) => Offer(
  id: row.id,
  itemId: row.itemId,
  url: row.url,
  shopName: row.shopName,
  fetchMode: row.fetchMode,
  resolvedMethod: row.resolvedMethod,
  lastPrice: row.lastPrice,
  lastCurrency: row.lastCurrency,
  lastAvailability: row.lastAvailability,
  lastStatus: row.lastStatus,
  lastError: row.lastError,
  lastCheckedAt: row.lastCheckedAt,
);
