import 'package:workmanager/workmanager.dart';

import '../calculators/schedule_calculator.dart';
import '../database/app_database.dart';
import '../utils/app_version.dart';
import 'http_page_fetcher.dart';
import 'log_service.dart';
import 'notification_service.dart';
import 'price_check_service.dart';
import 'scheduler_service.dart';

/// WorkManager entry point (Android). Must stay top-level and annotated, or
/// AOT tree-shaking removes it from release builds.
@pragma('vm:entry-point')
void callbackDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    if (task != kBackgroundTaskName) return true;
    final log = await LogService.open();
    final db = AppDatabase.openForIsolate();
    try {
      log.info('Background run started');
      final notifications = NotificationService(log: log);
      await notifications.initialize();
      final http = HttpPageFetcher(
        dio: HttpPageFetcher.createDio(appVersion: await loadAppVersion()),
        log: log,
      );
      final items = await db.itemsDao.getAll();
      await runPriceChecks(
        db: db,
        items: ScheduleCalculator.dueItems(items, DateTime.now()),
        http: http,
        // A headless WebView in this isolate is unproven (REQUIREMENTS R3);
        // such items are deferred to the next foreground catch-up.
        webView: null,
        notifier: notifications,
        log: log,
        clock: DateTime.now,
        deferWebViewItems: true,
      );
      await _enqueueNext(db, log);
      return true;
    } catch (e, st) {
      log.error('Background run failed', e, st);
      return false;
    } finally {
      await db.close();
    }
  });
}

Future<void> _enqueueNext(AppDatabase db, LogService log) async {
  final items = await db.itemsDao.getAll();
  final now = DateTime.now();
  final next = ScheduleCalculator.nextDueOverall(items, now);
  if (next == null) return;
  await Workmanager().registerOneOffTask(
    kBackgroundTaskName,
    kBackgroundTaskName,
    initialDelay: next.difference(now),
    constraints: Constraints(networkType: NetworkType.connected),
    // Not `replace`: this code runs inside the unique work itself, and
    // `replace` would cancel the running task. `update` maps to Android's
    // APPEND_OR_REPLACE, which chains the next run behind this one.
    existingWorkPolicy: ExistingWorkPolicy.update,
  );
  log.info('Next run (WorkManager) at $next');
}
