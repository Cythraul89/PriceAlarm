import 'dart:async';

import 'package:decimal/decimal.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/calculators/alarm_evaluator.dart';
import '../../core/calculators/schedule_calculator.dart';
import '../../core/models/enums.dart';
import '../../core/models/item.dart';
import '../../core/models/item_draft.dart';
import '../../core/models/offer.dart';
import '../../core/providers.dart';

// ── Read side ───────────────────────────────────────────────────────────────

final itemsStreamProvider = StreamProvider<List<Item>>(
  (ref) => ref.watch(appDatabaseProvider).itemsDao.watchAll(),
);

final allOffersStreamProvider = StreamProvider<List<Offer>>(
  (ref) => ref.watch(appDatabaseProvider).offersDao.watchAll(),
);

class ItemOverview {
  const ItemOverview({
    required this.item,
    required this.offers,
    required this.bestPrice,
    required this.bestShop,
    required this.failingOffers,
    required this.nextDue,
  });

  final Item item;
  final List<Offer> offers;
  final Decimal? bestPrice;
  final String? bestShop;

  /// Offers whose last check did not succeed.
  final int failingOffers;
  final DateTime nextDue;
}

/// Items with their offers and derived status, alarms first, then by name.
final itemOverviewsProvider = Provider<AsyncValue<List<ItemOverview>>>((ref) {
  final items = ref.watch(itemsStreamProvider);
  final offers = ref.watch(allOffersStreamProvider);
  if (items is AsyncError) return AsyncError(items.error!, items.stackTrace!);
  if (offers is AsyncError) {
    return AsyncError(offers.error!, offers.stackTrace!);
  }
  // Both streams must have delivered; a still-loading offer stream would
  // otherwise show every item as "no price".
  final itemList = items.valueOrNull;
  final offerList = offers.valueOrNull;
  if (itemList == null || offerList == null) return const AsyncLoading();

  final now = DateTime.now();
  final overviews = [
    for (final item in itemList) _overview(item, offerList, now),
  ]..sort(_byAlarmThenName);
  return AsyncData(overviews);
});

ItemOverview _overview(Item item, List<Offer> allOffers, DateTime now) {
  final offers = allOffers.where((o) => o.itemId == item.id).toList();
  final best = AlarmEvaluator.bestKnown(item.currency, [
    for (final o in offers)
      if (o.lastStatus == CheckStatus.ok)
        (shopName: o.shopName, price: o.lastPrice, currency: o.lastCurrency),
  ]);
  return ItemOverview(
    item: item,
    offers: offers,
    bestPrice: best?.price,
    bestShop: best?.shop,
    failingOffers: offers
        .where((o) => o.lastStatus != null && o.lastStatus != CheckStatus.ok)
        .length,
    nextDue: ScheduleCalculator.nextDue(item.checkTime, now),
  );
}

int _byAlarmThenName(ItemOverview a, ItemOverview b) {
  if (a.item.alarmActive != b.item.alarmActive) {
    return a.item.alarmActive ? -1 : 1;
  }
  return a.item.name.toLowerCase().compareTo(b.item.name.toLowerCase());
}

// ── Write side ──────────────────────────────────────────────────────────────

class ItemActions {
  ItemActions(this._ref);

  final Ref _ref;

  /// Saves the item and its offers. A new item is checked right away so it
  /// shows a price (and learns each offer's fetch method) without waiting
  /// for its first scheduled run. The check is not awaited — it can take
  /// up to a minute with the WebView fallback; the detail screen updates
  /// through its streams. Errors are logged inside the service.
  Future<String> save(ItemDraft draft) async {
    final db = _ref.read(appDatabaseProvider);
    final id = await db.itemsDao.saveDraft(draft, now: DateTime.now().toUtc());
    if (draft.id == null) {
      unawaited(_ref.read(priceCheckServiceProvider).runItem(id));
    }
    await _ref.read(schedulerServiceProvider).reschedule();
    return id;
  }

  Future<void> delete(String id) async {
    await _ref.read(appDatabaseProvider).itemsDao.deleteById(id);
    await _ref.read(schedulerServiceProvider).reschedule();
  }

  Future<void> setEnabled(String id, bool enabled) async {
    await _ref.read(appDatabaseProvider).itemsDao.setEnabled(id, enabled);
    await _ref.read(schedulerServiceProvider).reschedule();
  }

  Future<void> checkNow(String id) =>
      _ref.read(priceCheckServiceProvider).runItem(id);

  Future<void> checkAll() =>
      _ref.read(priceCheckServiceProvider).runAllEnabled();
}

final itemActionsProvider = Provider<ItemActions>(ItemActions.new);
