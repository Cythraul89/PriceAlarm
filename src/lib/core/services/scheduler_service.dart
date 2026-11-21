import 'dart:async';
import 'dart:io';

import '../calculators/schedule_calculator.dart';
import '../database/app_database.dart';
import 'background_worker.dart';
import 'log_service.dart';
import 'price_check_service.dart';

/// Decides *when* runs happen (ARCHITECTURE 6). Android: one exact
/// alarm-clock alarm (android_alarm_manager_plus) that runs in the
/// background and re-schedules itself. All other platforms: an in-app timer
/// while the app runs, plus catch-up on start/resume.
class SchedulerService {
  SchedulerService({
    required this.db,
    required this.checks,
    required this.log,
    required this.exactAlarmsAllowed,
    DateTime Function()? clock,
  }) : clock = clock ?? DateTime.now;

  final AppDatabase db;
  final PriceCheckService checks;
  final LogService log;

  /// Android exact-alarm permission check (NotificationService).
  final Future<bool> Function() exactAlarmsAllowed;
  final DateTime Function() clock;

  Timer? _timer;

  /// App start / resume: run what was missed, then plan the next run.
  Future<void> catchUpAndReschedule() async {
    await checks.runDue();
    await reschedule();
  }

  /// Re-plan after any change to items or after a run.
  Future<void> reschedule() async {
    final items = await db.itemsDao.getAll();
    final now = clock();
    final next = ScheduleCalculator.nextDueOverall(items, now);
    _timer?.cancel();
    _timer = null;

    if (Platform.isAndroid) {
      await scheduleAndroidRun(
        next,
        exactAllowed: await exactAlarmsAllowed(),
        log: log,
      );
      return;
    }
    if (next == null) return;
    _timer = Timer(next.difference(now), () {
      unawaited(catchUpAndReschedule());
    });
    log.info('Next run (timer) at $next');
  }

  void dispose() => _timer?.cancel();
}
