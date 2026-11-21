import 'package:decimal/decimal.dart';
import 'package:equatable/equatable.dart';

import '../models/check_outcome.dart';
import '../models/enums.dart';

class AlarmDecision extends Equatable {
  const AlarmDecision({
    required this.active,
    required this.fire,
    this.bestPrice,
    this.bestShop,
  });

  /// New value of `Item.alarmActive` (price at/below target — display).
  final bool active;

  /// Ring now.
  final bool fire;

  /// Lowest comparable price of this run; `null` when no offer was usable.
  final Decimal? bestPrice;
  final String? bestShop;

  @override
  List<Object?> get props => [active, fire, bestPrice, bestShop];
}

/// Implements REQUIREMENTS 5.2 — the "price at or below target" trigger.
abstract final class AlarmEvaluator {
  /// Rings at every daily cycle in which a check finds the best price at or
  /// below the target — at most once per cycle, whichever check of the
  /// cycle (scheduled, catch-up, manual) finds it first.
  ///
  /// [cycleStart] is the latest due instant of the item; [lastAlarmAt] the
  /// last ring. [complete] is false when the run skipped offers (Android
  /// background run without WebView): then the result may fire, but cannot
  /// clear `active`, because a skipped offer may still be below the target.
  static AlarmDecision evaluate({
    required Decimal targetPrice,
    required String currency,
    required bool wasActive,
    required DateTime? lastAlarmAt,
    required DateTime cycleStart,
    required bool complete,
    required List<({String shopName, CheckOutcome outcome})> results,
  }) {
    Decimal? best;
    String? bestShop;
    for (final r in results) {
      final outcome = r.outcome;
      if (outcome.status != CheckStatus.ok || outcome.price == null) continue;
      // A page without a currency is assumed to be in the item currency;
      // a different currency is never compared (no FX in v0.1).
      final pageCurrency = outcome.currency ?? currency;
      if (pageCurrency != currency) continue;
      if (best == null || outcome.price! < best) {
        best = outcome.price;
        bestShop = r.shopName;
      }
    }

    // No usable price: keep the state; an outage never rings.
    if (best == null) {
      return AlarmDecision(active: wasActive, fire: false);
    }
    final reached = best <= targetPrice;
    final rangThisCycle =
        lastAlarmAt != null && !lastAlarmAt.isBefore(cycleStart);
    return AlarmDecision(
      active: complete ? reached : (wasActive || reached),
      fire: reached && !rangThisCycle,
      bestPrice: best,
      bestShop: bestShop,
    );
  }

  /// Best current price for display, from the offers' last successful
  /// checks in the item currency.
  static ({Decimal price, String shop})? bestKnown(
    String currency,
    Iterable<({String shopName, Decimal? price, String? currency})> offers,
  ) {
    ({Decimal price, String shop})? best;
    for (final o in offers) {
      final price = o.price;
      if (price == null || (o.currency ?? currency) != currency) continue;
      if (best == null || price < best.price) {
        best = (price: price, shop: o.shopName);
      }
    }
    return best;
  }
}
