import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:workmanager/workmanager.dart';

import 'app.dart';
import 'core/database/app_database.dart';
import 'core/providers.dart';
import 'core/services/alarm_sound.dart';
import 'core/services/background_worker.dart';
import 'core/services/http_page_fetcher.dart';
import 'core/services/log_service.dart';
import 'core/services/notification_service.dart';
import 'core/services/webview_page_fetcher.dart';
import 'core/utils/app_version.dart';
import 'features/settings/about_screen.dart';

LogService? _log;

void main() {
  runZonedGuarded(_main, (error, stackTrace) {
    _log?.error('Uncaught error', error, stackTrace);
  });
}

Future<void> _main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // ── Logging ────────────────────────────────────────────────────────────────
  final log = await LogService.open();
  _log = log;
  log.trim();
  log.info('App start');
  final originalDebugPrint = debugPrint;
  debugPrint = (message, {wrapWidth}) {
    originalDebugPrint(message, wrapWidth: wrapWidth);
    if (message != null) log.info(message);
  };
  final originalOnError = FlutterError.onError;
  FlutterError.onError = (details) {
    // Original handler first; calling presentError here would recurse.
    originalOnError?.call(details);
    log.error('FlutterError', details.exception, details.stack);
  };

  LicenseRegistry.addLicense(
    () => Stream.value(
      const LicenseEntryWithLineBreaks(['PriceAlarm'], kLicenseNotice),
    ),
  );

  // ── Optional subsystems — a failure must not block startup ─────────────────
  if (Platform.isAndroid) {
    try {
      await Workmanager().initialize(callbackDispatcher);
    } catch (e, st) {
      log.error('WorkManager init failed', e, st);
    }
  }

  final notifications = NotificationService(log: log);
  String? launchItemId;
  try {
    launchItemId = await notifications.initialize();
  } catch (e, st) {
    log.error('Notification init failed', e, st);
  }

  // ── Singletons ─────────────────────────────────────────────────────────────
  final db = AppDatabase();
  final version = await loadAppVersion();
  final http = HttpPageFetcher(
    dio: HttpPageFetcher.createDio(appVersion: version),
    log: log,
  );
  final AlarmSound alarmSound = AudioAlarmSound.isNeeded
      ? AudioAlarmSound(log: log)
      : const SilentAlarmSound();
  final webView = WebViewPageFetcher.isSupportedPlatform
      ? WebViewPageFetcher(log: log)
      : null;

  final container = ProviderContainer(
    overrides: [
      appDatabaseProvider.overrideWithValue(db),
      logServiceProvider.overrideWithValue(log),
      notificationServiceProvider.overrideWithValue(notifications),
      httpPageFetcherProvider.overrideWithValue(http),
      webViewPageFetcherProvider.overrideWithValue(webView),
      alarmSoundProvider.overrideWithValue(alarmSound),
      appVersionProvider.overrideWithValue(version),
    ],
  );

  runApp(
    UncontrolledProviderScope(
      container: container,
      child: const PriceAlarmApp(),
    ),
  );

  // ── Post-first-frame work ──────────────────────────────────────────────────
  WidgetsBinding.instance.addPostFrameCallback((_) async {
    // Notification tap or full-screen launch over the lock screen → the
    // alarm screen, where the user stops the ringing (REQUIREMENTS 5.3.3).
    // push, not go: "Stop" pops back to wherever the user was.
    if (launchItemId != null) appRouter.push('/alarm/$launchItemId');
    notifications.tappedItemIds.listen((id) => appRouter.push('/alarm/$id'));
    container
        .read(alarmControllerProvider)
        .rings
        .listen((alarm) => appRouter.push('/alarm/${alarm.itemId}'));

    final scheduler = container.read(schedulerServiceProvider);
    // Registers itself as a binding observer on construction and lives as
    // long as the app.
    AppLifecycleListener(
      onResume: () => unawaited(scheduler.catchUpAndReschedule()),
    );
    if (Platform.isAndroid) await notifications.requestPermission();
    await scheduler.catchUpAndReschedule();
  });
}
