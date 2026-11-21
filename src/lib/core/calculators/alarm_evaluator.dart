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

  /// New value of `Item.alarmActive`.
  final bool active;

  /// Raise a notification now (false → true transition only).
  final bool fire;

  /// Lowest comparable price of this run; `null` when no offer was usable.
  final Decimal? bestPrice;
  final String? bestShop;

  @override
  List<Object?> get props => [active, fire, bestPrice, bestShop];
}

/// Implements REQUIREMENTS 5.2 — the "price at or below target" trigger.
abstract final class AlarmEvaluator {
  static AlarmDecision evaluate({
    required Decimal targetPrice,
    required String currency,
    required bool wasActive,
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

    // No usable price: keep the state so an outage neither fires nor
    // silently re-arms the alarm.
    if (best == null) {
      return AlarmDecision(active: wasActive, fire: false);
    }
    final active = best <= targetPrice;
    return AlarmDecision(
      active: active,
      fire: active && !wasActive,
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
