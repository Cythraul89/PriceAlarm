import 'dart:ui';

import 'package:android_alarm_manager_plus/android_alarm_manager_plus.dart';
import 'package:material_ui/material_ui.dart' show WidgetsFlutterBinding;

import '../calculators/schedule_calculator.dart';
import '../database/app_database.dart';
import '../utils/app_version.dart';
import 'http_page_fetcher.dart';
import 'log_service.dart';
import 'notification_service.dart';
import 'price_check_service.dart';
import 'webview_page_fetcher.dart';

/// Id of the single Android alarm that triggers the next price run.
/// Scheduling with the same id replaces the pending alarm.
const kPriceRunAlarmId = 4711;

/// Schedules the next Android background run (ARCHITECTURE 6).
///
/// With the exact-alarm permission it uses `setAlarmClock` — the mechanism
/// alarm-clock apps use: fires on time in Doze, and the system leaves Doze
/// shortly before so the network is available. Without the permission it
/// falls back to `setAndAllowWhileIdle`, which also fires in Doze but may be
/// delayed by several minutes.
Future<void> scheduleAndroidRun(
  DateTime? next, {
  required bool exactAllowed,
  required LogService log,
}) async {
  try {
    if (next == null) {
      await AndroidAlarmManager.cancel(kPriceRunAlarmId);
      log.info('No run scheduled (no enabled item)');
      return;
    }
    final ok = await AndroidAlarmManager.oneShotAt(
      next,
      kPriceRunAlarmId,
      priceRunCallback,
      alarmClock: exactAllowed,
      exact: exactAllowed,
      allowWhileIdle: true,
      wakeup: true,
      rescheduleOnReboot: true,
    );
    log.info(
      'Next run (${exactAllowed ? 'exact alarm' : 'inexact alarm'}) at $next'
      '${ok ? '' : ' — scheduling FAILED'}',
    );
  } catch (e, st) {
    log.error('Scheduling the background run failed', e, st);
  }
}

/// Alarm entry point (Android). Runs in a background isolate started by
/// android_alarm_manager_plus — also when the app is closed. Must stay
/// top-level and annotated, or AOT tree-shaking removes it.
@pragma('vm:entry-point')
Future<void> priceRunCallback() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Plugins registered from Dart (e.g. path_provider_android) are not
  // registered automatically in a background isolate.
  DartPluginRegistrant.ensureInitialized();

  final log = await LogService.open();
  final db = AppDatabase.openForIsolate();
  final notifications = NotificationService(log: log);
  try {
    log.info('Background run started');
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
      // A headless WebView in this isolate is unproven on every device
      // (REQUIREMENTS R3): it is tried, and a WebView offer that fails here
      // stays due for the next foreground catch-up (deferWebViewOffers).
      webView: WebViewPageFetcher(log: log),
      notifier: notifications,
      log: log,
      clock: DateTime.now,
      scope: RunScope.dueOffers,
      deferWebViewOffers: true,
    );
  } catch (e, st) {
    log.error('Background run failed', e, st);
  } finally {
    // Always plan the next run, also after a failure — otherwise the chain
    // of alarms ends until the app is opened again.
    try {
      final items = await db.itemsDao.getAll();
      await scheduleAndroidRun(
        ScheduleCalculator.nextDueOverall(items, DateTime.now()),
        exactAllowed: await notifications.canScheduleExactAlarms(),
        log: log,
      );
    } catch (e, st) {
      log.error('Re-scheduling after the background run failed', e, st);
    }
    await db.close();
  }
}
