import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'database/app_database.dart';
import 'services/alarm_controller.dart';
import 'services/alarm_sound.dart';
import 'services/backup_service.dart';
import 'services/log_service.dart';
import 'services/notification_service.dart';
import 'services/page_fetcher.dart';
import 'services/price_check_service.dart';
import 'services/scheduler_service.dart';

// ── Singletons overridden in main.dart ──────────────────────────────────────
// Each throws so a missing override (in main.dart or a test) fails loudly
// instead of silently constructing a real client.

final appDatabaseProvider = Provider<AppDatabase>(
  (ref) => throw UnimplementedError('appDatabaseProvider must be overridden'),
);

final logServiceProvider = Provider<LogService>(
  (ref) => throw UnimplementedError('logServiceProvider must be overridden'),
);

final notificationServiceProvider = Provider<NotificationService>(
  (ref) => throw UnimplementedError(
    'notificationServiceProvider must be overridden',
  ),
);

final httpPageFetcherProvider = Provider<PageFetcher>(
  (ref) =>
      throw UnimplementedError('httpPageFetcherProvider must be overridden'),
);

/// `null` on platforms without a headless WebView.
final webViewPageFetcherProvider = Provider<PageFetcher?>(
  (ref) => throw UnimplementedError(
    'webViewPageFetcherProvider must be overridden',
  ),
);

/// `SilentAlarmSound` on Android, where the notification rings itself.
final alarmSoundProvider = Provider<AlarmSound>(
  (ref) => throw UnimplementedError('alarmSoundProvider must be overridden'),
);

final appVersionProvider = Provider<String>(
  (ref) => throw UnimplementedError('appVersionProvider must be overridden'),
);

// ── Composed services ───────────────────────────────────────────────────────

final alarmControllerProvider = Provider<AlarmController>((ref) {
  final controller = AlarmController(
    notifications: ref.watch(notificationServiceProvider),
    sound: ref.watch(alarmSoundProvider),
    log: ref.watch(logServiceProvider),
  );
  ref.onDispose(controller.dispose);
  return controller;
});

final priceCheckServiceProvider = Provider<PriceCheckService>(
  (ref) => PriceCheckService(
    db: ref.watch(appDatabaseProvider),
    http: ref.watch(httpPageFetcherProvider),
    webView: ref.watch(webViewPageFetcherProvider),
    // The controller rings in-app on top of the notification.
    notifier: ref.watch(alarmControllerProvider),
    log: ref.watch(logServiceProvider),
  ),
);

final schedulerServiceProvider = Provider<SchedulerService>((ref) {
  final scheduler = SchedulerService(
    db: ref.watch(appDatabaseProvider),
    checks: ref.watch(priceCheckServiceProvider),
    log: ref.watch(logServiceProvider),
    exactAlarmsAllowed: ref.watch(notificationServiceProvider).canScheduleExactAlarms,
  );
  ref.onDispose(scheduler.dispose);
  return scheduler;
});

final backupServiceProvider = Provider<BackupService>(
  (ref) => BackupService(db: ref.watch(appDatabaseProvider)),
);
