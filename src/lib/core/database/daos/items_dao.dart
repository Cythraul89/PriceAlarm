import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../../models/item.dart';
import '../../models/item_draft.dart';
import '../app_database.dart';
import '../tables/items_table.dart';
import '../tables/offers_table.dart';

part 'items_dao.g.dart';

@DriftAccessor(tables: [Items, Offers])
class ItemsDao extends DatabaseAccessor<AppDatabase> with _$ItemsDaoMixin {
  ItemsDao(super.attachedDatabase);

  Stream<List<Item>> watchAll() =>
      (select(items)..orderBy([(t) => OrderingTerm.asc(t.name)]))
          .map(_itemFromRow)
          .watch();

  Future<List<Item>> getAll() => select(items).map(_itemFromRow).get();

  Stream<Item?> watchById(String id) =>
      (select(items)..where((t) => t.id.equals(id)))
          .map(_itemFromRow)
          .watchSingleOrNull();

  Future<Item?> findById(String id) =>
      (select(items)..where((t) => t.id.equals(id)))
          .map(_itemFromRow)
          .getSingleOrNull();

  /// Inserts or updates the item and reconciles its offers in one
  /// transaction. Returns the item id.
  ///
  /// An offer whose URL changed loses its last-check data, because that
  /// data described a different page. A changed target price re-arms the
  /// alarm (REQUIREMENTS 5.2.4).
  Future<String> saveDraft(ItemDraft draft, {required DateTime now}) =>
      transaction(() async {
        final id = draft.id ?? const Uuid().v4();
        final existing = draft.id == null ? null : await findById(id);

        if (existing == null) {
          await into(items).insert(
            ItemsCompanion.insert(
              id: id,
              name: draft.name,
              targetPrice: draft.targetPrice,
              checkTime: Value(draft.checkTime),
              enabled: Value(draft.enabled),
              createdAt: now,
            ),
          );
        } else {
          final targetChanged = existing.targetPrice != draft.targetPrice;
          await (update(items)..where((t) => t.id.equals(id))).write(
            ItemsCompanion(
              name: Value(draft.name),
              targetPrice: Value(draft.targetPrice),
              checkTime: Value(draft.checkTime),
              enabled: Value(draft.enabled),
              alarmActive: targetChanged
                  ? const Value(false)
                  : const Value.absent(),
              // A new target may ring again in the current cycle.
              lastAlarmAt: targetChanged
                  ? const Value(null)
                  : const Value.absent(),
            ),
          );
        }

        final currentOffers = await (select(
          offers,
        )..where((t) => t.itemId.equals(id))).get();
        final keptIds = draft.offers.map((o) => o.id).whereType<String>();
        for (final row in currentOffers) {
          if (!keptIds.contains(row.id)) {
            await (delete(offers)..where((t) => t.id.equals(row.id))).go();
          }
        }

        for (final offer in draft.offers) {
          final current = currentOffers
              .where((row) => row.id == offer.id)
              .firstOrNull;
          if (current == null) {
            await into(offers).insert(
              OffersCompanion.insert(
                id: offer.id ?? const Uuid().v4(),
                itemId: id,
                url: offer.url,
                shopName: offer.shopName,
                fetchMode: Value(offer.fetchMode),
              ),
            );
            continue;
          }
          final urlChanged = current.url != offer.url;
          await (update(offers)..where((t) => t.id.equals(current.id))).write(
            OffersCompanion(
              url: Value(offer.url),
              shopName: Value(offer.shopName),
              fetchMode: Value(offer.fetchMode),
              resolvedMethod: urlChanged
                  ? const Value(null)
                  : const Value.absent(),
              lastPrice: urlChanged ? const Value(null) : const Value.absent(),
              lastCurrency: urlChanged
                  ? const Value(null)
                  : const Value.absent(),
              lastAvailability: urlChanged
                  ? const Value(null)
                  : const Value.absent(),
              lastStatus: urlChanged ? const Value(null) : const Value.absent(),
              lastError: urlChanged ? const Value(null) : const Value.absent(),
              lastCheckedAt: urlChanged
                  ? const Value(null)
                  : const Value.absent(),
            ),
          );
        }
        return id;
      });

  Future<void> setEnabled(String id, bool enabled) =>
      (update(items)..where((t) => t.id.equals(id))).write(
        ItemsCompanion(enabled: Value(enabled)),
      );

  /// Targeted write of the run outcome — never a whole-row save.
  /// [lastRunAt] is only written for a complete run, [lastAlarmAt] only
  /// when the alarm rang.
  Future<void> recordRun(
    String id, {
    required bool alarmActive,
    DateTime? lastRunAt,
    DateTime? lastAlarmAt,
  }) => (update(items)..where((t) => t.id.equals(id))).write(
    ItemsCompanion(
      alarmActive: Value(alarmActive),
      lastRunAt: lastRunAt == null ? const Value.absent() : Value(lastRunAt),
      lastAlarmAt: lastAlarmAt == null
          ? const Value.absent()
          : Value(lastAlarmAt),
    ),
  );

  Future<int> deleteById(String id) =>
      (delete(items)..where((t) => t.id.equals(id))).go();
}

Item _itemFromRow(ItemRow row) => Item(
  id: row.id,
  name: row.name,
  targetPrice: row.targetPrice,
  currency: row.currency,
  checkTime: row.checkTime,
  enabled: row.enabled,
  alarmActive: row.alarmActive,
  lastRunAt: row.lastRunAt,
  createdAt: row.createdAt,
  lastAlarmAt: row.lastAlarmAt,
);
