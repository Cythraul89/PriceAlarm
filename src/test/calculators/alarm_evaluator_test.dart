import 'package:decimal/decimal.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:price_alarm/core/calculators/alarm_evaluator.dart';
import 'package:price_alarm/core/models/check_outcome.dart';
import 'package:price_alarm/core/models/enums.dart';

({String shopName, CheckOutcome outcome}) _ok(
  String shop,
  String price, {
  String? currency = 'CHF',
}) => (
  shopName: shop,
  outcome: CheckOutcome(
    status: CheckStatus.ok,
    method: FetchMethod.http,
    price: Decimal.parse(price),
    currency: currency,
  ),
);

({String shopName, CheckOutcome outcome}) _failed(
  String shop,
  CheckStatus status,
) => (
  shopName: shop,
  outcome: CheckOutcome(status: status, error: 'x'),
);

// Daily cycle starting today 08:00 (local wall clock, as in production).
final _cycleStart = DateTime(2026, 11, 21, 8);

AlarmDecision _evaluate({
  String target = '2000',
  bool wasActive = false,
  DateTime? lastAlarmAt,
  bool complete = true,
  required List<({String shopName, CheckOutcome outcome})> results,
}) => AlarmEvaluator.evaluate(
  targetPrice: Decimal.parse(target),
  currency: 'CHF',
  wasActive: wasActive,
  lastAlarmAt: lastAlarmAt,
  cycleStart: _cycleStart,
  complete: complete,
  results: results,
);

void main() {
  group('AlarmEvaluator.evaluate', () {
    test('rings when the best price is at or below the target', () {
      final d = _evaluate(
        results: [_ok('Brack', '2209.00'), _ok('Galaxus', '1999.00')],
      );
      expect(d.bestPrice, Decimal.parse('1999.00'));
      expect(d.bestShop, 'Galaxus');
      expect(d.active, isTrue);
      expect(d.fire, isTrue);
    });

    test('a price exactly at the target counts as reached', () {
      final d = _evaluate(results: [_ok('Brack', '2000.00')]);
      expect(d.fire, isTrue);
    });

    test('rings again in a new daily cycle while the price stays low', () {
      // Rang yesterday at 08:01 — today's cycle (08:00) has not rung yet.
      final d = _evaluate(
        wasActive: true,
        lastAlarmAt: DateTime(2026, 11, 20, 8, 1),
        results: [_ok('Brack', '1900')],
      );
      expect(d.active, isTrue);
      expect(d.fire, isTrue);
    });

    test('rings at most once per cycle (catch-up, Check now)', () {
      final d = _evaluate(
        wasActive: true,
        lastAlarmAt: DateTime(2026, 11, 21, 8, 1),
        results: [_ok('Brack', '1900')],
      );
      expect(d.active, isTrue);
      expect(d.fire, isFalse);
    });

    test('a price above the target clears active and does not ring', () {
      final d = _evaluate(wasActive: true, results: [_ok('Brack', '2000.05')]);
      expect(d.active, isFalse);
      expect(d.fire, isFalse);
    });

    test('a partial run can ring but never clears active', () {
      // Background run checked only Brack; Galaxus (WebView) was skipped
      // and may still be below the target.
      final above = _evaluate(
        wasActive: true,
        complete: false,
        results: [_ok('Brack', '2209')],
      );
      expect(above.active, isTrue);
      expect(above.fire, isFalse);

      final below = _evaluate(complete: false, results: [_ok('Brack', '1950')]);
      expect(below.active, isTrue);
      expect(below.fire, isTrue);
    });

    test('a run without any ok offer keeps the state and does not ring', () {
      final active = _evaluate(
        wasActive: true,
        results: [_failed('Galaxus', CheckStatus.blocked)],
      );
      expect(active.active, isTrue);
      expect(active.fire, isFalse);
      expect(active.bestPrice, isNull);

      final inactive = _evaluate(
        results: [_failed('Galaxus', CheckStatus.networkError)],
      );
      expect(inactive.active, isFalse);
      expect(inactive.fire, isFalse);
    });

    test('failed offers are ignored next to an ok offer', () {
      final d = _evaluate(
        results: [
          _failed('Galaxus', CheckStatus.blocked),
          _ok('Brack', '1950'),
        ],
      );
      expect(d.bestShop, 'Brack');
      expect(d.fire, isTrue);
    });

    test('an offer in a foreign currency is never compared', () {
      final d = _evaluate(results: [_ok('Amazon', '1500', currency: 'EUR')]);
      expect(d.bestPrice, isNull);
      expect(d.active, isFalse);
      expect(d.fire, isFalse);
    });

    test('a page without currency is assumed to be in the item currency', () {
      final d = _evaluate(results: [_ok('Shop', '1500', currency: null)]);
      expect(d.bestPrice, Decimal.fromInt(1500));
      expect(d.fire, isTrue);
    });
  });

  group('AlarmEvaluator.bestKnown', () {
    test('returns the lowest price in the item currency', () {
      final best = AlarmEvaluator.bestKnown('CHF', [
        (shopName: 'A', price: Decimal.parse('10'), currency: 'CHF'),
        (shopName: 'B', price: Decimal.parse('5'), currency: 'EUR'),
        (shopName: 'C', price: Decimal.parse('8'), currency: null),
        (shopName: 'D', price: null, currency: 'CHF'),
      ]);
      expect(best?.price, Decimal.parse('8'));
      expect(best?.shop, 'C');
    });

    test('returns null without any price', () {
      expect(AlarmEvaluator.bestKnown('CHF', const []), isNull);
    });
  });
}
