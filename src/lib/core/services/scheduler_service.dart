import 'dart:async';
import 'dart:io';

import 'package:workmanager/workmanager.dart';

import '../calculators/schedule_calculator.dart';
import '../database/app_database.dart';
import 'log_service.dart';
import 'price_check_service.dart';

const kBackgroundTaskName = 'price-run';

/// Decides *when* runs happen (ARCHITECTURE 6). Android: one chained
/// WorkManager one-off task. All other platforms: an in-app timer while the
/// app runs, plus catch-up on start/resume.
class SchedulerService {
  SchedulerService({
    required this.db,
    required this.checks,
    required this.log,
    DateTime Function()? clock,
  }) : clock = clock ?? DateTime.now;

  final AppDatabase db;
  final PriceCheckService checks;
  final LogService log;
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
      await _scheduleAndroid(next, now);
      return;
    }
    if (next == null) return;
    _timer = Timer(next.difference(now), () {
      unawaited(catchUpAndReschedule());
    });
    log.info('Next run (timer) at $next');
  }

  void dispose() => _timer?.cancel();

  Future<void> _scheduleAndroid(DateTime? next, DateTime now) async {
    try {
      if (next == null) {
        await Workmanager().cancelByUniqueName(kBackgroundTaskName);
        return;
      }
      await Workmanager().registerOneOffTask(
        kBackgroundTaskName,
        kBackgroundTaskName,
        initialDelay: next.difference(now),
        constraints: Constraints(networkType: NetworkType.connected),
        existingWorkPolicy: ExistingWorkPolicy.replace,
      );
      log.info('Next run (WorkManager) at $next');
    } catch (e, st) {
      log.error('Scheduling the background run failed', e, st);
    }
  }
}
