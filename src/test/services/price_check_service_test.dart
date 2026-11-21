import 'dart:io';

import 'package:decimal/decimal.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:price_alarm/core/database/app_database.dart';
import 'package:price_alarm/core/models/check_outcome.dart';
import 'package:price_alarm/core/models/enums.dart';
import 'package:price_alarm/core/models/item_draft.dart';
import 'package:price_alarm/core/services/log_service.dart';
import 'package:price_alarm/core/services/page_fetcher.dart';
import 'package:price_alarm/core/services/price_check_service.dart';

String _product(String price) =>
    '<script type="application/ld+json">{"@type":"Product","offers":'
    '{"@type":"Offer","price":"$price","priceCurrency":"CHF"}}</script>';

/// Serves canned results per URL and records every call.
class _FakeFetcher implements PageFetcher {
  _FakeFetcher(this.responses);

  final Map<String, PageFetchResult> responses;
  final calls = <String>[];

  @override
  Future<PageFetchResult> fetch(Uri url) async {
    calls.add(url.toString());
    return responses[url.toString()] ??
        const PageNetworkError('no canned response');
  }
}

class _FakeNotifier implements AlarmNotifier {
  final alarms = <({String itemName, Decimal price, String shopName})>[];

  @override
  Future<void> showAlarm({
    required String itemId,
    required String itemName,
    required Decimal price,
    required Decimal targetPrice,
    required String currency,
    required String shopName,
  }) async => alarms.add((itemName: itemName, price: price, shopName: shopName));

  @override
  Future<void> cancelAlarm(String itemId) async {}
}

const _brack = 'https://www.brack.ch/r9700';
const _galaxus = 'https://www.galaxus.ch/r9700';

void main() {
  group('checkOffer', () {
    test('auto: HTTP success needs no WebView', () async {
      final http = _FakeFetcher({_brack: PageFetched(_product('2209.00'))});
      final webView = _FakeFetcher({});
      final outcome = await checkOffer(
        url: Uri.parse(_brack),
        mode: FetchMode.auto,
        http: http,
        webView: webView,
      );
      expect(outcome.status, CheckStatus.ok);
      expect(outcome.method, FetchMethod.http);
      expect(outcome.price, Decimal.parse('2209.00'));
      expect(webView.calls, isEmpty);
    });

    test('auto: blocked HTTP escalates to the WebView', () async {
      final http = _FakeFetcher({_galaxus: const PageBlocked('HTTP 403')});
      final webView = _FakeFetcher({_galaxus: PageFetched(_product('2149'))});
      final outcome = await checkOffer(
        url: Uri.parse(_galaxus),
        mode: FetchMode.auto,
        http: http,
        webView: webView,
      );
      expect(outcome.status, CheckStatus.ok);
      expect(outcome.method, FetchMethod.webview);
    });

    test('auto: a page without price escalates to the WebView', () async {
      final http = _FakeFetcher({_galaxus: const PageFetched('<html></html>')});
      final webView = _FakeFetcher({_galaxus: PageFetched(_product('2149'))});
      final outcome = await checkOffer(
        url: Uri.parse(_galaxus),
        mode: FetchMode.auto,
        http: http,
        webView: webView,
      );
      expect(outcome.method, FetchMethod.webview);
    });

    test('auto: a resolved WebView method is tried first', () async {
      final http = _FakeFetcher({});
      final webView = _FakeFetcher({_galaxus: PageFetched(_product('2149'))});
      await checkOffer(
        url: Uri.parse(_galaxus),
        mode: FetchMode.auto,
        resolvedMethod: FetchMethod.webview,
        http: http,
        webView: webView,
      );
      expect(http.calls, isEmpty);
    });

    test('a network error does not escalate', () async {
      final http = _FakeFetcher({_brack: const PageNetworkError('timeout')});
      final webView = _FakeFetcher({_brack: PageFetched(_product('1'))});
      final outcome = await checkOffer(
        url: Uri.parse(_brack),
        mode: FetchMode.auto,
        http: http,
        webView: webView,
      );
      expect(outcome.status, CheckStatus.networkError);
      expect(webView.calls, isEmpty);
    });

    test('without a WebView, a blocked page stays blocked with the reason',
        () async {
      final http = _FakeFetcher({_galaxus: const PageBlocked('HTTP 403')});
      final outcome = await checkOffer(
        url: Uri.parse(_galaxus),
        mode: FetchMode.auto,
        http: http,
        webView: null,
      );
      expect(outcome.status, CheckStatus.blocked);
      expect(outcome.error, contains('HTTP 403'));
      expect(outcome.error, contains('WebView not available'));
    });

    test('webview mode without a WebView is unsupported', () async {
      final outcome = await checkOffer(
        url: Uri.parse(_galaxus),
        mode: FetchMode.webview,
        http: _FakeFetcher({}),
        webView: null,
      );
      expect(outcome.status, CheckStatus.unsupported);
    });

    test('a challenge page served with 200 counts as blocked', () async {
      final outcome = await checkOffer(
        url: Uri.parse(_galaxus),
        mode: FetchMode.http,
        http: _FakeFetcher({
          _galaxus: const PageFetched('<title>Access Denied</title>'),
        }),
      );
      expect(outcome.status, CheckStatus.blocked);
    });
  });

  group('runPriceChecks', () {
    late AppDatabase db;
    late LogService log;
    late Directory tmp;
    late _FakeNotifier notifier;
    // Local wall clock, as in production; the item checks daily at 08:00.
    late DateTime now;

    setUp(() async {
      db = AppDatabase.forTesting(NativeDatabase.memory());
      tmp = await Directory.systemTemp.createTemp('price_alarm_test');
      log = LogService(File('${tmp.path}/test.log'));
      notifier = _FakeNotifier();
      now = DateTime(2026, 11, 21, 8, 5);
    });

    tearDown(() async {
      await db.close();
      await tmp.delete(recursive: true);
    });

    Future<String> createItem({String target = '2200'}) =>
        db.itemsDao.saveDraft(
          ItemDraft(
            name: 'R9700',
            targetPrice: Decimal.parse(target),
            checkTime: 480,
            enabled: true,
            offers: const [
              OfferDraft(
                url: _brack,
                shopName: 'Brack',
                fetchMode: FetchMode.auto,
              ),
              OfferDraft(
                url: _galaxus,
                shopName: 'Galaxus',
                fetchMode: FetchMode.auto,
              ),
            ],
          ),
          now: now.subtract(const Duration(days: 2)).toUtc(),
        );

    Future<void> run(
      String id,
      _FakeFetcher http,
      _FakeFetcher? webView, {
      RunScope scope = RunScope.allOffers,
      bool defer = false,
    }) async {
      final item = (await db.itemsDao.findById(id))!;
      await runPriceChecks(
        db: db,
        items: [item],
        http: http,
        webView: webView,
        notifier: notifier,
        log: log,
        clock: () => now,
        scope: scope,
        deferWebViewOffers: defer,
      );
    }

    /// Galaxus learned the WebView method in an earlier foreground run.
    Future<void> galaxusSeenViaWebViewYesterday(String id) async {
      final galaxus = (await db.offersDao.getByItem(
        id,
      )).firstWhere((o) => o.shopName == 'Galaxus');
      await db.offersDao.recordCheck(
        galaxus.id,
        CheckOutcome(
          status: CheckStatus.ok,
          method: FetchMethod.webview,
          price: Decimal.parse('2276.00'),
          currency: 'CHF',
        ),
        checkedAt: now.subtract(const Duration(days: 1)).toUtc(),
        rememberMethod: true,
      );
    }

    test('records history and offer state, rings once per daily cycle', () async {
      final id = await createItem();
      final http = _FakeFetcher({
        _brack: PageFetched(_product('2209.00')),
        _galaxus: const PageBlocked('HTTP 403'),
      });
      final webView = _FakeFetcher({_galaxus: PageFetched(_product('2149.00'))});

      await run(id, http, webView);

      final item = await db.itemsDao.findById(id);
      expect(item?.alarmActive, isTrue);
      // Drift returns local DateTimes; compare the instant.
      expect(item?.lastRunAt?.isAtSameMomentAs(now), isTrue);
      expect(item?.lastAlarmAt?.isAtSameMomentAs(now), isTrue);
      expect(notifier.alarms.single.shopName, 'Galaxus');
      expect(notifier.alarms.single.price, Decimal.parse('2149.00'));
      final galaxus = (await db.offersDao.getByItem(
        id,
      )).firstWhere((o) => o.shopName == 'Galaxus');
      expect(galaxus.resolvedMethod, FetchMethod.webview);
      expect(
        await db.priceChecksDao.watchByItem(id, limit: 10).first,
        hasLength(2),
      );

      // Same cycle ("Check now" an hour later): no second ring.
      now = now.add(const Duration(hours: 1));
      await run(id, http, webView);
      expect(notifier.alarms, hasLength(1));

      // Next day's scheduled run, price still below target: rings again.
      now = DateTime(2026, 11, 22, 8, 1);
      await run(id, http, webView, scope: RunScope.dueOffers);
      expect(notifier.alarms, hasLength(2));
    });

    test('Android background run: checks the HTTP offer and rings, leaves '
        'the WebView offer due', () async {
      final id = await createItem(target: '2300');
      await galaxusSeenViaWebViewYesterday(id);
      final http = _FakeFetcher({_brack: PageFetched(_product('2209.00'))});

      await run(id, http, null, scope: RunScope.dueOffers, defer: true);

      expect(http.calls, [_brack]);
      expect(notifier.alarms.single.shopName, 'Brack');
      final item = await db.itemsDao.findById(id);
      // Not a complete run: the foreground catch-up still checks Galaxus.
      expect(item?.lastRunAt, isNull);
      expect(item?.lastAlarmAt?.isAtSameMomentAs(now), isTrue);
    });

    test('foreground catch-up then checks only the skipped WebView offer and '
        'does not ring twice in the cycle', () async {
      final id = await createItem(target: '2300');
      await galaxusSeenViaWebViewYesterday(id);
      final http = _FakeFetcher({_brack: PageFetched(_product('2209.00'))});
      await run(id, http, null, scope: RunScope.dueOffers, defer: true);

      now = now.add(const Duration(minutes: 30)); // user opens the app
      final webView = _FakeFetcher({_galaxus: PageFetched(_product('2276.00'))});
      await run(id, http, webView, scope: RunScope.dueOffers);

      expect(http.calls, [_brack]); // Brack was not fetched again
      expect(webView.calls, [_galaxus]);
      expect(notifier.alarms, hasLength(1));
      final item = await db.itemsDao.findById(id);
      expect(item?.lastRunAt?.isAtSameMomentAs(now), isTrue);
    });

    test('a background run with only WebView offers due changes nothing', () async {
      final id = await createItem();
      await galaxusSeenViaWebViewYesterday(id);
      // Brack was already checked in this cycle.
      final brack = (await db.offersDao.getByItem(
        id,
      )).firstWhere((o) => o.shopName == 'Brack');
      await db.offersDao.recordCheck(
        brack.id,
        CheckOutcome(
          status: CheckStatus.ok,
          method: FetchMethod.http,
          price: Decimal.parse('2209.00'),
          currency: 'CHF',
        ),
        checkedAt: now.toUtc(),
        rememberMethod: true,
      );
      final http = _FakeFetcher({});

      await run(id, http, null, scope: RunScope.dueOffers, defer: true);

      expect(http.calls, isEmpty);
      expect(notifier.alarms, isEmpty);
      expect((await db.itemsDao.findById(id))?.lastRunAt, isNull);
    });
  });
}
