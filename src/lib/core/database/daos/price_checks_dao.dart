import 'package:drift/drift.dart';

import '../../models/check_outcome.dart';
import '../../models/price_check.dart';
import '../app_database.dart';
import '../tables/offers_table.dart';
import '../tables/price_checks_table.dart';

part 'price_checks_dao.g.dart';

@DriftAccessor(tables: [PriceChecks, Offers])
class PriceChecksDao extends DatabaseAccessor<AppDatabase>
    with _$PriceChecksDaoMixin {
  PriceChecksDao(super.attachedDatabase);

  Future<int> insertCheck(
    String offerId,
    CheckOutcome outcome, {
    required DateTime checkedAt,
  }) => into(priceChecks).insert(
    PriceChecksCompanion.insert(
      offerId: offerId,
      checkedAt: checkedAt,
      status: outcome.status,
      method: Value(outcome.method),
      price: Value(outcome.price),
      currency: Value(outcome.currency),
      availability: Value(outcome.availability),
      error: Value(outcome.error),
    ),
  );

  /// History of all offers of [itemId], newest first.
  Stream<List<PriceCheck>> watchByItem(String itemId, {required int limit}) {
    final query =
        select(priceChecks).join([
            innerJoin(offers, offers.id.equalsExp(priceChecks.offerId)),
          ])
          ..where(offers.itemId.equals(itemId))
          ..orderBy([
            OrderingTerm.desc(priceChecks.checkedAt),
            OrderingTerm.desc(priceChecks.id),
          ])
          ..limit(limit);
    return query.watch().map(
      (rows) => rows.map((row) {
        final check = row.readTable(priceChecks);
        return PriceCheck(
          id: check.id,
          offerId: check.offerId,
          shopName: row.readTable(offers).shopName,
          checkedAt: check.checkedAt,
          status: check.status,
          method: check.method,
          price: check.price,
          currency: check.currency,
          availability: check.availability,
          error: check.error,
        );
      }).toList(),
    );
  }

  Future<int> deleteOlderThan(DateTime cutoff) =>
      (delete(priceChecks)..where((t) => t.checkedAt.isSmallerThanValue(cutoff)))
          .go();
}
