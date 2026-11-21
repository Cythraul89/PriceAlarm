import 'package:decimal/decimal.dart';

import '../calculators/alarm_evaluator.dart';
import '../calculators/schedule_calculator.dart';
import '../database/app_database.dart';
import '../models/check_outcome.dart';
import '../models/enums.dart';
import '../models/item.dart';
import 'log_service.dart';
import 'page_fetcher.dart';
import 'price_extractor.dart';

/// Raises and silences alarms; implemented by `NotificationService`
/// (background) and `AlarmController` (app running).
abstract interface class AlarmNotifier {
  Future<void> showAlarm({
    required String itemId,
    required String itemName,
    required Decimal price,
    required Decimal targetPrice,
    required String currency,
    required String shopName,
  });

  Future<void> cancelAlarm(String itemId);
}

const kHistoryRetention = Duration(days: 365);

/// Checks one offer once, with the `auto` escalation of REQUIREMENTS 4.2.
/// [webView] is `null` where no WebView can be used (Linux, Android
/// background isolate).
Future<CheckOutcome> checkOffer({
  required Uri url,
  required FetchMode mode,
  FetchMethod? resolvedMethod,
  required PageFetcher http,
  PageFetcher? webView,
}) async {
  final methods = switch (mode) {
    FetchMode.http => [FetchMethod.http],
    FetchMode.webview => [FetchMethod.webview],
    FetchMode.auto =>
      resolvedMethod == FetchMethod.webview
          ? [FetchMethod.webview, FetchMethod.http]
          : [FetchMethod.http, FetchMethod.webview],
  };

  CheckOutcome? previous;
  for (final method in methods) {
    final fetcher = method == FetchMethod.http ? http : webView;
    final result = fetcher == null
        ? const PageUnsupported('WebView not available here')
        : await fetcher.fetch(url);
    final outcome = _toOutcome(result, method);

    switch (outcome.status) {
      case CheckStatus.ok:
        return outcome;
      // The network itself failed — a second transport will not help.
      case CheckStatus.networkError:
        return outcome;
      case CheckStatus.unsupported when previous != null:
        // Keep the informative first failure, explain why no fallback ran.
        return CheckOutcome(
          status: previous.status,
          method: previous.method,
          error: '${previous.error}; ${outcome.error}',
        );
      case CheckStatus.blocked ||
          CheckStatus.noPrice ||
          CheckStatus.unsupported:
        previous = outcome;
    }
  }
  return previous!;
}

CheckOutcome _toOutcome(PageFetchResult result, FetchMethod method) =>
    switch (result) {
      PageBlocked(:final reason) => CheckOutcome(
        status: CheckStatus.blocked,
        method: method,
        error: reason,
      ),
      PageNetworkError(:final reason) => CheckOutcome(
        status: CheckStatus.networkError,
        method: method,
        error: reason,
      ),
      PageUnsupported(:final reason) => CheckOutcome(
        status: CheckStatus.unsupported,
        error: reason,
      ),
      PageFetched(:final html) => _extract(html, method),
    };

CheckOutcome _extract(String html, FetchMethod method) {
  final extracted = PriceExtractor.extract(html);
  if (extracted != null) {
    return CheckOutcome(
      status: CheckStatus.ok,
      method: method,
      price: extracted.price,
      currency: extracted.currency,
      availability: extracted.availability,
    );
  }
  // Only consulted when no price was found, so a stray "captcha" string on
  // a normal product page cannot turn a success into a failure.
  return PriceExtractor.looksLikeChallenge(html)
      ? CheckOutcome(
          status: CheckStatus.blocked,
          method: method,
          error: 'Bot challenge page',
        )
      : CheckOutcome(
          status: CheckStatus.noPrice,
          method: method,
          error: 'No structured price data on the page',
        );
}

/// Outcome of one item run.
typedef ItemRunResult = ({String itemId, AlarmDecision? decision});

/// Which offers of an item a run checks.
enum RunScope {
  /// Every offer — "Check now", "Check all", a new item.
  allOffers,

  /// Only offers not checked since the item's latest due instant —
  /// scheduled runs and catch-ups.
  dueOffers,
}

/// Runs [items] (ARCHITECTURE 5.2). Shared by the UI and the Android
/// background run, so both behave identically.
///
/// With [deferWebViewOffers] (Android background, no WebView there), offers
/// that need a WebView are skipped and stay due; the item's other offers are
/// still checked and may ring. The item only counts as run (`lastRunAt`)
/// once no offer was skipped, so the next foreground catch-up checks the
/// skipped ones (REQUIREMENTS §9, R3).
Future<List<ItemRunResult>> runPriceChecks({
  required AppDatabase db,
  required List<Item> items,
  required PageFetcher http,
  required PageFetcher? webView,
  required AlarmNotifier notifier,
  required LogService log,
  required DateTime Function() clock,
  RunScope scope = RunScope.allOffers,
  bool deferWebViewOffers = false,
}) async {
  final results = <ItemRunResult>[];
  for (final item in items) {
    final now = clock();
    final allOffers = await db.offersDao.getByItem(item.id);
    final selected = scope == RunScope.allOffers
        ? allOffers
        : allOffers
              .where((o) => ScheduleCalculator.isOfferDue(item, o, now))
              .toList();
    final toCheck = deferWebViewOffers
        ? selected.where((o) => !o.needsWebView).toList()
        : selected;
    final skipped = selected.length - toCheck.length;
    if (skipped > 0) {
      log.info('Run ${item.name}: $skipped offer(s) deferred (need WebView)');
    }
    if (toCheck.isEmpty) {
      results.add((itemId: item.id, decision: null));
      continue;
    }

    final outcomes = <({String shopName, CheckOutcome outcome})>[];
    // Sequential on purpose: one page load at a time.
    for (final offer in toCheck) {
      final outcome = await checkOffer(
        url: Uri.parse(offer.url),
        mode: offer.fetchMode,
        resolvedMethod: offer.resolvedMethod,
        http: http,
        webView: webView,
      );
      final checkedAt = clock().toUtc();
      await db.priceChecksDao.insertCheck(
        offer.id,
        outcome,
        checkedAt: checkedAt,
      );
      await db.offersDao.recordCheck(
        offer.id,
        outcome,
        checkedAt: checkedAt,
        rememberMethod: offer.fetchMode == FetchMode.auto,
      );
      log.info(
        'Check ${item.name} @ ${offer.shopName}: ${outcome.status.name}'
        '${outcome.price == null ? '' : ' ${outcome.price}'}'
        '${outcome.error == null ? '' : ' (${outcome.error})'}',
      );
      outcomes.add((shopName: offer.shopName, outcome: outcome));
    }

    final decision = AlarmEvaluator.evaluate(
      targetPrice: item.targetPrice,
      currency: item.currency,
      wasActive: item.alarmActive,
      lastAlarmAt: item.lastAlarmAt,
      cycleStart: ScheduleCalculator.latestDue(item.checkTime, now),
      // Only a run over every offer may clear `active`.
      complete: toCheck.length == allOffers.length,
      results: outcomes,
    );
    final finishedAt = clock().toUtc();
    await db.itemsDao.recordRun(
      item.id,
      alarmActive: decision.active,
      lastRunAt: skipped == 0 ? finishedAt : null,
      lastAlarmAt: decision.fire ? finishedAt : null,
    );
    if (decision.fire) {
      try {
        await notifier.showAlarm(
          itemId: item.id,
          itemName: item.name,
          price: decision.bestPrice!,
          targetPrice: item.targetPrice,
          currency: item.currency,
          shopName: decision.bestShop!,
        );
      } catch (e, st) {
        log.error('Alarm notification for ${item.name} failed', e, st);
      }
    }
    results.add((itemId: item.id, decision: decision));
  }
  await db.priceChecksDao.deleteOlderThan(
    clock().toUtc().subtract(kHistoryRetention),
  );
  return results;
}

/// UI-side entry point with a re-entrancy guard per item, so a timer run
/// and a "Check now" tap never check the same item concurrently.
class PriceCheckService {
  PriceCheckService({
    required this.db,
    required this.http,
    required this.webView,
    required this.notifier,
    required this.log,
    DateTime Function()? clock,
  }) : clock = clock ?? DateTime.now;

  final AppDatabase db;
  final PageFetcher http;
  final PageFetcher? webView;
  final AlarmNotifier notifier;
  final LogService log;
  final DateTime Function() clock;

  final _running = <String>{};

  Future<void> runItem(String itemId) async {
    final item = await db.itemsDao.findById(itemId);
    if (item != null) await _run([item], RunScope.allOffers);
  }

  Future<void> runAllEnabled() async {
    final items = await db.itemsDao.getAll();
    await _run(items.where((i) => i.enabled).toList(), RunScope.allOffers);
  }

  /// Catch-up (REQUIREMENTS 5.1.2): the due offers of every item whose due
  /// time passed since its last complete run.
  Future<void> runDue() async {
    final items = await db.itemsDao.getAll();
    await _run(ScheduleCalculator.dueItems(items, clock()), RunScope.dueOffers);
  }

  /// One check without persisting anything — the form's "Test" button.
  Future<CheckOutcome> testOffer(String url, FetchMode mode) => checkOffer(
    url: Uri.parse(url),
    mode: mode,
    http: http,
    webView: webView,
  );

  Future<void> _run(List<Item> items, RunScope scope) async {
    final toRun = items.where((i) => !_running.contains(i.id)).toList();
    if (toRun.isEmpty) return;
    _running.addAll(toRun.map((i) => i.id));
    try {
      await runPriceChecks(
        db: db,
        items: toRun,
        http: http,
        webView: webView,
        notifier: notifier,
        log: log,
        clock: clock,
        scope: scope,
      );
    } catch (e, st) {
      log.error('Price run failed', e, st);
    } finally {
      _running.removeAll(toRun.map((i) => i.id));
    }
  }
}
